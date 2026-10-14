-- Domain flags route independently of diagnostic text; legacy callers retain their seam.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checks = 0
local mixedFailures = {}
local FLAVORS = { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }
-- Runtime owners a general or unit request reaches; the mixed-batch matrix records them by name.
local ROUTED = { "MSUF_ApplyAllCastbarsAndSync", "MSUF_ApplyBarOutlineThickness_All", "MSUF_ApplyCastbarUnitAndSync",
    "MSUF_Castbars_OnSettingsChanged",
    "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", "MSUF_ApplyRoundedUnitframes",
    "MSUF_ClassPower_Apply", "MSUF_DetachedPowerBar_RefreshTextures", "MSUF_ForceTextLayoutForUnitKey",
    "MSUF_GF_RefreshPreviewBox", "MSUF_GF_RefreshPreviewLayout", "MSUF_RefreshAllFrameColors", "MSUF_RefreshAllFrames",
    "MSUF_RefreshAllIdentityColors", "MSUF_RefreshAllPowerTextColors", "MSUF_RefreshAllUnitAlphas",
    "MSUF_RefreshMouseoverHighlight", "MSUF_RefreshUnitDispelOverlays", "MSUF_UpdateAllBarGradients",
    "MSUF_UpdateAllBarTextures_Immediate", "MSUF_UpdateAllFonts_Immediate", "MSUF_UpdateCastbarTextures_Immediate" }
-- One legacy request per row: label, reason (false = nil), extra flags. Flagless rows rely on reason inference.
local PARTNERS = {
    { "flagless FONT", "FONT", {} },
    { "flagless nil reason", false, {} },
    { "flagless every keyword", "FONT_POWER_ALPHA_CLASSPOWER", {} },
    { "explicit text", "unrelated", { text = true } },
    { "legacy castbar flag", "FONT", { castbar = true } },
}
local ORDERS = { "TL", "LT", "TLT", "LTL" }
local TYPED_REASONS = { false, "FONT_POWER_ALPHA_CLASSPOWER" }
local UNIT_ONLY = { auras = true, applyUnit = true }
-- Owners each general domain reaches on its own (identical on every client and to the frozen base's flag routes).
local SOLO = {
    aggroBorder = "MSUF_ApplyBarOutlineThickness_All,GF.RefreshVisuals",
    alpha = "MSUF_RefreshAllUnitAlphas",
    altMana = "MSUF_ClassPower_Apply",
    applyUnit = "",
    auras = "",
    barGradients = "MSUF_UpdateAllBarGradients",
    barOutline = "MSUF_ApplyBarOutlineThickness_All,GF.RefreshVisuals",
    bars = "MSUF_UpdateAllBarTextures_Immediate",
    bossTargetBorder = "UF.RefreshBorders",
    castbar = "MSUF_ApplyAllCastbarsAndSync",
    castbarTextures = "MSUF_UpdateCastbarTextures_Immediate",
    classPowerPlayerHP = "MSUF_ClassPower_Apply",
    classpower = "MSUF_ClassPower_Apply",
    colors = "MSUF_RefreshAllFrameColors,GF.RefreshColors",
    detachedPowerBar = "MSUF_DetachedPowerBar_RefreshTextures,MSUF_ApplyPowerBarEmbedLayout_ForUnitKey,MSUF_ClassPower_Apply",
    dispelPurgeBorder = "MSUF_ApplyBarOutlineThickness_All,MSUF_RefreshUnitDispelOverlays,GF.RefreshVisuals,Auras.MenuModel.Apply",
    fonts = "MSUF_UpdateAllFonts_Immediate,MSUF_RefreshAllIdentityColors,MSUF_RefreshAllPowerTextColors,GF.RefreshFonts",
    frames = "MSUF_RefreshAllFrames",
    groupAggroRole = "GF.RefreshVisuals",
    highlightPriority = "UF.RefreshBorders,GF.RefreshVisuals",
    mouseoverHighlight = "MSUF_ApplyRoundedUnitframes,MSUF_RefreshMouseoverHighlight",
    power = "MSUF_ApplyPowerBarEmbedLayout_All",
    roundedBars = "MSUF_ApplyRoundedUnitframes,GF.RefreshVisuals,MSUF_GF_RefreshPreviewLayout,"
        .. "MSUF_GF_RefreshPreviewLayout,MSUF_GF_RefreshPreviewLayout,MSUF_GF_RefreshPreviewBox",
    text = "MSUF_ForceTextLayoutForUnitKey",
    visual = "MSUF_RefreshAllFrames",
}
local BUILDERS = { "RequestColors", "RequestFonts", "RequestBars", "RequestBarGradients", "RequestBarOutline",
    "RequestRoundedBars", "RequestAggroBorder", "RequestGroupAggroRole", "RequestDispelPurgeBorder",
    "RequestBossTargetBorder", "RequestHighlightBorders", "RequestHighlightPriority", "RequestCastbars" }
local BUILDER_SCOPE = { RequestGroupAggroRole = "party" }
local UNIT_DOMAINS = { "text", "power", "alpha", "fonts", "castbar", "auras", "detachedPowerBar", "applyUnit" }
local function CoreWorld(flavor)
    local world = World.New(root, flavor)
    local suffix = world.client.tocSuffix or flavor
    world:LoadGraph("MidnightSimpleUnitFrames",
        World.Graph(root, World.CoreTOC(suffix), "enUS", world.client.isForever and "camelot" or nil), world.core)
    assert(world:FirstFailure() == nil, "core boot failed")
    return world, assert(world.core.ApplyService, "typed core apply missing")
end
local function InstallRecorders(world)
    local trace = {}
    local function Record(name)
        return function()
            trace[#trace + 1] = name
            return true
        end
    end
    for _, name in ipairs(ROUTED) do world.env[name] = Record(name) end
    local ns = world.core
    for name, value in pairs(ns.GF) do
        if type(value) == "function" and name ~= "MergeDirtyMask" then ns.GF[name] = Record("GF." .. name) end
    end
    for _, name in ipairs({ "Apply", "RefreshElements", "RefreshBorders" }) do ns.UF[name] = Record("UF." .. name) end
    local auras = ns.MSUF_Auras3
    for _, name in ipairs({ "InvalidateUnitRuntimeConfig", "InvalidateNativeVisualInputs", "RefreshEditPreview" }) do
        auras[name] = Record("Auras." .. name)
    end
    auras.MenuModel.Apply = Record("Auras.MenuModel.Apply")
    return trace
end
local function Sorted(text)
    local parts = {}
    for part in text:gmatch("[^,]+") do parts[#parts + 1] = part end
    table.sort(parts)
    return table.concat(parts, ",")
end
-- Every request domain, mixed with legacy requests in every order, executes exactly what the legacy part
-- would execute plus the explicit typed domains. An explicit domain from either source ends reason inference.
local function MixedMatrix(flavor)
    local world, apply = CoreWorld(flavor)
    local trace = InstallRecorders(world)
    local count = 0
    local function Run(request)
        for i = #trace, 1, -1 do trace[i] = nil end
        request()
        apply.Flush()
        count = count + 1
        return table.concat(trace, ",")
    end
    local function Legacy(partner)
        local opts = { applyAll = false, preview = false }
        for key, value in pairs(partner[3]) do opts[key] = value end
        apply.RequestGeneral(partner[2] or nil, opts)
    end
    local function Fail(what, expected, got)
        mixedFailures[#mixedFailures + 1] = flavor .. " " .. what .. " expected [" .. expected .. "] got [" .. got .. "]"
    end
    local domains = {}
    for _, name in pairs(apply.Domains) do domains[#domains + 1] = name end
    table.sort(domains)
    for _, domain in ipairs(domains) do
        local solo = Run(function()
            apply.RequestGeneralDomains("solo", { [domain] = true, applyAll = false, preview = false })
        end)
        if SOLO[domain] == nil then Fail(domain .. " has no pinned route", "a SOLO entry", solo) end
        if solo ~= SOLO[domain] then Fail(domain .. " solo route drifted", tostring(SOLO[domain]), solo) end
        for _, partner in ipairs(PARTNERS) do
            local expected
            if UNIT_ONLY[domain] then
                expected = Run(function() Legacy(partner) end)
            else
                local flags = { [domain] = true, applyAll = false, preview = false }
                for key, value in pairs(partner[3]) do flags[key] = value end
                expected = Run(function() apply.RequestGeneralDomains("union", flags) end)
            end
            for _, order in ipairs(ORDERS) do
                for _, reason in ipairs(TYPED_REASONS) do
                    local got = Run(function()
                        for i = 1, #order do
                            if order:sub(i, i) == "T" then
                                apply.RequestGeneralDomains(reason or nil, { [domain] = true, applyAll = false, preview = false })
                            else
                                Legacy(partner)
                            end
                        end
                    end)
                    if got ~= expected then
                        Fail(domain .. " + " .. partner[1] .. " order " .. order .. " typed reason " .. tostring(reason),
                            expected, got)
                    end
                end
            end
        end
    end
    -- The internal typed builders carry their explicit domains: a flagless legacy request never adds work.
    -- A scope keeps RequestColors on the queued path (its global form pushes colors immediately); group
    -- aggro refreshes only group scopes.
    for _, builder in ipairs(BUILDERS) do
        local expected = Run(function() apply[builder]("builder", BUILDER_SCOPE[builder] or "player") end)
        if expected == "" then Fail(builder .. " solo route is empty", "routes", expected) end
        for _, partner in ipairs(PARTNERS) do
            if next(partner[3]) == nil then
                for _, order in ipairs(ORDERS) do
                    local got = Run(function()
                        for i = 1, #order do
                            if order:sub(i, i) == "T" then apply[builder]("builder", BUILDER_SCOPE[builder] or "player") else Legacy(partner) end
                        end
                    end)
                    if got ~= expected then Fail(builder .. " + " .. partner[1] .. " order " .. order, expected, got) end
                end
            end
        end
    end
    -- Unit requests keep their own queue: legacy general inference is unaffected by a typed unit domain,
    -- and legacy and typed unit requests for one unit coalesce exactly like one combined request.
    local function UnitRequest(method, names)
        local opts = { notify = false, preview = false }
        for _, name in ipairs(names) do opts[name] = true end
        apply[method]("player", "unit", opts)
    end
    for _, domain in ipairs(UNIT_DOMAINS) do
        local solo = Run(function() UnitRequest("RequestUnitDomains", { domain }) end)
        if solo == "" then Fail("unit " .. domain .. " solo route is empty", "routes", solo) end
        for _, partner in ipairs(PARTNERS) do
            local expected = Sorted(solo .. "," .. Run(function() Legacy(partner) end))
            for _, order in ipairs({ "TL", "LT" }) do
                local got = Run(function()
                    for i = 1, #order do
                        if order:sub(i, i) == "T" then UnitRequest("RequestUnitDomains", { domain }) else Legacy(partner) end
                    end
                end)
                if Sorted(got) ~= expected then Fail("unit " .. domain .. " + " .. partner[1] .. " order " .. order, expected, got) end
            end
        end
        for _, other in ipairs(UNIT_DOMAINS) do
            if other ~= domain then
                local expected = Run(function() UnitRequest("RequestUnitDomains", { domain, other }) end)
                for _, methods in ipairs({ { "RequestUnit", "RequestUnitDomains" }, { "RequestUnitDomains", "RequestUnit" } }) do
                    local got = Run(function()
                        UnitRequest(methods[1], { domain })
                        UnitRequest(methods[2], { other })
                    end)
                    if got ~= expected then Fail("unit " .. domain .. " then " .. other .. " via " .. methods[1], expected, got) end
                end
            end
        end
    end
    return count
end
for _, flavor in ipairs(FLAVORS) do
    local world, apply = CoreWorld(flavor)
    local D = assert(apply.Domains)
    local env = world.env
    local calls = {}
    env.MSUF_ForceTextLayoutForUnitKey = function() calls[#calls + 1] = "text" end
    env.MSUF_ApplyPowerBarEmbedLayout_All = function() calls[#calls + 1] = "power" end
    env.MSUF_RefreshAllUnitAlphas = function() calls[#calls + 1] = "alpha" end
    env.MSUF_ClassPower_Apply = function() calls[#calls + 1] = "classpower" end
    env.MSUF_ApplyAllCastbarsAndSync = function() calls[#calls + 1] = "castbar" end
    for _, case in ipairs({ { D.TEXT, "text" }, { D.POWER, "power" }, { D.ALPHA, "alpha" },
        { D.CLASSPOWER, "classpower" } }) do
        for _, reason in ipairs({ "unrelated", "FONT_POWER_ALPHA_CLASSPOWER", "renamed diagnostic" }) do
            calls = {}
            apply.RequestGeneralDomains(reason, { [case[1]] = true, applyAll = false, preview = false })
            apply.Flush()
            assert(table.concat(calls, ",") == case[2], "typed route changed with reason: " .. reason)
            checks = checks + 1
        end
    end
    calls = {}
    apply.RequestGeneralDomains("FONT_POWER_ALPHA_CLASSPOWER", { applyAll = false, preview = false })
    apply.Flush()
    assert(#calls == 0, "typed empty request inferred domains from its reason")
    calls = {}
    apply.RequestGeneral("FONT_POWER", { applyAll = false, preview = false })
    apply.Flush()
    assert(table.concat(calls, ",") == "text,power", "legacy reason compatibility drifted")
    calls = {}
    apply.RequestGeneral("FONT_POWER", { [D.TEXT] = true, applyAll = false, preview = false })
    apply.Flush()
    assert(table.concat(calls, ",") == "text", "explicit flags lost precedence over legacy reasons")
    -- These legacy-only routes are pinned against the frozen base, including nil retention.
    local legacyCases = {
        { { false }, "" },
        { { false, false }, "" },
        { { "FONT" }, "text" },
        { { "POWER" }, "power" },
        { { "FONT", false }, "text" },
        { { false, "POWER" }, "power" },
        { { "FONT", "POWER", false }, "power" },
        { { "POWER", "FONT", false, false }, "text" },
        { { "FONT", false, "unrelated", false }, "" },
    }
    for _, case in ipairs(legacyCases) do
        for _, diagnostic in ipairs({ "FONT", "POWER", "FONT_POWER_ALPHA_CLASSPOWER", "unrelated", false }) do
            for _, order in ipairs({ "before", "after", "between", "repeated" }) do
                calls = {}
                local opts = { applyAll = false, preview = false }
                local function Typed()
                    apply.RequestGeneralDomains(diagnostic or nil, opts)
                end
                if order == "before" or order == "repeated" then Typed() end
                for _, reason in ipairs(case[1]) do
                    apply.RequestGeneral(reason or nil, opts)
                    if order == "between" or order == "repeated" then Typed() end
                end
                if order == "after" or order == "repeated" then Typed() end
                apply.Flush()
                if table.concat(calls, ",") ~= case[2] then
                    mixedFailures[#mixedFailures + 1] = flavor .. " mixed " .. order
                        .. " diagnostic " .. tostring(diagnostic) .. " expected " .. case[2]
                        .. " got " .. table.concat(calls, ",")
                end
                checks = checks + 1
            end
        end
    end
    -- Explicit merged domains still suppress reason inference in either request order.
    for _, typedFirst in ipairs({ true, false }) do
        calls = {}
        local opts = { text = true, applyAll = false, preview = false }
        if typedFirst then apply.RequestGeneralDomains("POWER", opts) end
        apply.RequestGeneral("POWER", { applyAll = false, preview = false })
        if not typedFirst then apply.RequestGeneralDomains("POWER", opts) end
        apply.Flush()
        assert(table.concat(calls, ",") == "text", "mixed explicit flags lost precedence")
        checks = checks + 1
    end
    -- Castbar queuing must retain typed precedence, including after repeated legacy requests.
    for _, typedFirst in ipairs({ true, false }) do
        for _, legacyText in ipairs({ true, false }) do
            calls = {}
            local typedOpts = { [D.CASTBAR] = true, applyAll = false, preview = false }
            local legacyOpts = { text = legacyText, applyAll = false, preview = false }
            if typedFirst then apply.RequestGeneralDomains("unrelated", typedOpts) end
            apply.RequestGeneral("FONT", legacyOpts)
            if not typedFirst then apply.RequestGeneralDomains("unrelated", typedOpts) end
            apply.Flush()
            local expected = legacyText and "text,castbar" or "castbar"
            if table.concat(calls, ",") ~= expected then
                mixedFailures[#mixedFailures + 1] = flavor .. " mixed castbar typedFirst=" .. tostring(typedFirst)
                    .. " legacyText=" .. tostring(legacyText) .. " expected " .. expected
                    .. " got " .. table.concat(calls, ",")
            end
            checks = checks + 1
        end
    end
    calls = {}
    apply.RequestGeneralDomains("unrelated", { [D.CASTBAR] = true, applyAll = false, preview = false })
    apply.RequestGeneral("FONT", { applyAll = false, preview = false })
    apply.RequestGeneralDomains("POWER", { applyAll = false, preview = false })
    apply.RequestGeneral(nil, { applyAll = false, preview = false })
    apply.RequestGeneralDomains(nil, { [D.CASTBAR] = true, applyAll = false, preview = false })
    apply.Flush()
    if table.concat(calls, ",") ~= "castbar" then
        mixedFailures[#mixedFailures + 1] = flavor .. " repeated castbar expected castbar got " .. table.concat(calls, ",")
    end
    checks = checks + 1
    -- Frozen legacy castbar-only requests still infer from FONT during coalescing.
    calls = {}
    apply.RequestGeneral("FONT", { castbar = true, applyAll = false, preview = false })
    apply.Flush()
    assert(table.concat(calls, ",") == "text,castbar", "legacy castbar-only inference drifted")
    checks = checks + 1
    calls = {}
    env.C_Timer.NewTimer, env.C_Timer.After = nil, nil
    apply.RequestGeneral("FONT", { applyAll = false, preview = false })
    assert(table.concat(calls, ",") == "text", "synchronous legacy flush lost reason compatibility")
    checks = checks + 4
    checks = checks + MixedMatrix(flavor)
end
assert(#mixedFailures == 0, #mixedFailures .. " mixed-batch failures, first:\n"
    .. table.concat(mixedFailures, "\n", 1, math.min(#mixedFailures, 12)))
print("PASS typed domain routing and legacy seam: " .. checks .. " checks across five clients")
