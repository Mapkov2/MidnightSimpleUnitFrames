local root = assert(arg[1]):gsub("\\", "/")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Encode(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        if type(value[key]) ~= "function" and type(value[key]) ~= "table" then
            out[#out + 1] = tostring(key) .. "=" .. tostring(value[key])
        end
    end
    return "{" .. table.concat(out, ",") .. "}"
end
local checksum, cases = 0, 0
local function Trace(line)
    for i = 1, #line + 1 do
        local byte = i <= #line and line:byte(i) or 10
        checksum = (checksum * 131 + byte) % 2147483647
    end
    cases = cases + 1
end
local flags = { "text", "power", "alpha", "fonts", "bars", "barGradients", "barOutline", "roundedBars",
    "aggroBorder", "groupAggroRole", "dispelPurgeBorder", "bossTargetBorder", "highlightPriority", "colors",
    "mouseoverHighlight", "castbar", "castbarTextures", "detachedPowerBar", "classpower", "classPower",
    "classPowerPlayerHP", "altMana", "visual", "frames" }
local methods = { "RequestColors", "RequestFonts", "RequestBars", "RequestBarGradients", "RequestBarOutline",
    "RequestRoundedBars", "RequestAggroBorder", "RequestGroupAggroRole", "RequestDispelPurgeBorder",
    "RequestBossTargetBorder", "RequestHighlightBorders", "RequestHighlightPriority" }
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, tostring(failure and failure.message))
    local env, ns = world.env, world.core
    env.MSUF_InitProfiles()
    local trace = {}
    local function Record(name)
        return function(...)
            local args = {}
            for i = 1, select("#", ...) do args[i] = Encode(select(i, ...)) end
            trace[#trace + 1] = name .. "(" .. table.concat(args, ",") .. ")"
            return true
        end
    end
    for name, value in pairs(env) do
        if name:match("^MSUF_") and type(value) == "function" then env[name] = Record(name) end
    end
    for name, value in pairs(ns.GF or {}) do
        if type(value) == "function" and name ~= "MergeDirtyMask" then ns.GF[name] = Record("GF." .. name) end
    end
    ns.UF.Apply = Record("UF.Apply")
    ns.UF.RefreshElements = Record("UF.RefreshElements")
    local a3 = ns.MSUF_Auras3
    for _, name in ipairs({ "InvalidateUnitRuntimeConfig", "InvalidateNativeVisualInputs", "RefreshEditPreview" }) do
        a3[name] = Record("Auras." .. name)
    end
    a3.MenuModel.Apply = Record("Auras.MenuModel.Apply")
    local M = ns.MSUF2
    M.ApplyGameplay = Record("Menu.ApplyGameplay")
    M.RefreshGFNativePreviews = Record("Menu.RefreshGFNativePreviews")
    local service = assert(M.ApplyService)
    local function Case(name, request)
        trace = {}
        local result = request()
        service.Flush()
        Trace(flavor .. "|" .. name .. "|" .. tostring(result) .. "|" .. table.concat(trace, ";"))
    end
    for _, flag in ipairs(flags) do
        Case("general:" .. flag, function()
            return service.RequestGeneral("oracle", { [flag] = true, applyAll = false, preview = false })
        end)
    end
    for _, flag in ipairs({ "text", "power", "alpha", "fonts", "castbar", "auras", "detachedPowerBar", "applyUnit" }) do
        Case("unit:" .. flag, function()
            return service.RequestUnit("player", "oracle", { [flag] = true, notify = false, preview = false })
        end)
    end
    for _, method in ipairs(methods) do
        for _, scope in ipairs({ "shared", "player", "party", "raid" }) do
            Case(method .. ":" .. scope, function() return service[method]("oracle", scope) end)
        end
    end
    for _, reason in ipairs({ "FONT", "TEXT", "NAME", "POWER", "ALPHA", "OPACITY", "TRANSPARENCY",
        "CLASSPOWER", "CLASS_POWER", "CLASS POWER", "FONT_POWER_ALPHA_CLASSPOWER", "nothing", "font" }) do
        Case("legacy:reason:" .. reason, function()
            return service.RequestGeneral(reason, { applyAll = false, preview = false })
        end)
        Case("legacy:explicit:" .. reason, function()
            return service.RequestGeneral(reason, { text = true, applyAll = false, preview = false })
        end)
        Case("legacy:visual-false:" .. reason, function()
            return service.RequestGeneral(reason, { visual = false, applyAll = false, preview = false })
        end)
        Case("legacy:classpower-flags:" .. reason, function()
            return service.RequestClassPower(reason, { playerHP = true }, { applyAll = false, preview = false })
        end)
    end
    Case("legacy:merge:last-reason", function()
        service.RequestGeneral("FONT", { applyAll = false, preview = false })
        return service.RequestGeneral("POWER", { applyAll = false, preview = false })
    end)
    Case("legacy:merge:flag-precedence", function()
        service.RequestGeneral("FONT_POWER", { applyAll = false, preview = false })
        return service.RequestGeneral("ALPHA", { text = true, applyAll = false, preview = false })
    end)
    Case("general:full", function() return service.RequestGeneral("oracle") end)
    Case("unit:full", function() return service.RequestUnit("tot", "oracle") end)
    Case("castbars:all", function() return service.RequestCastbars("oracle") end)
    Case("castbars:boss2", function() return service.RequestCastbarUnit("boss2", "oracle") end)
    Case("auras:player", function() return service.RequestAuras("player", "oracle") end)
    Case("auras:shared", function() return service.RequestAuras("shared", "oracle", { visuals = true }) end)
    Case("auras:fonts", function() return service.RequestAuraFonts("shared", "oracle") end)
    Case("classpower:colors", function() return service.RequestClassPower("oracle", { colors = true }) end)
    Case("merge:targeted-full", function()
        service.RequestGeneral("oracle", { applyAll = false, text = true, preview = false })
        return service.RequestGeneral("oracle", { notify = false, fonts = true, preview = false })
    end)
    Case("merge:unit-notify", function()
        service.RequestUnit("player", "oracle", { notify = false, text = true, preview = false })
        return service.RequestUnit("player", "oracle", { preview = false })
    end)
    for _, scope in ipairs({ "party", "raid", "mythicraid", "priority", "group" }) do
        for _, mode in ipairs({ "visual", "layout", "fonts", "colors", "reset" }) do
            Case("group:" .. scope .. ":" .. mode, function() return service.RequestGroup(scope, mode, "oracle") end)
        end
        Case("group:dirty:" .. scope, function()
            return service.RequestGroupDirtyMask(scope, ns.GF.DIRTY_ALL, "oracle")
        end)
    end
    Case("group:reset", function() return service.RequestGroupReset("oracle") end)
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena", "tot", "focus_target", "unknown" }) do
        Case("unit:normalize:" .. unit, function() return service.RequestUnit(unit, "oracle", { preview = false }) end)
        Case("power:layout:" .. unit, function() return service.ApplyPowerLayout(unit) end)
    end
    Case("power:detached", function() return service.ApplyPowerLayout("player", true, false) end)
    Case("classpower:flags", function()
        return service.RequestClassPower("oracle", { anchor = true, syncNow = false },
            { classpower = true, preview = false, applyAll = false })
    end)
    Case("classpower:unit", function()
        return service.RequestClassPower("oracle", { playerHP = true },
            { unit = "player", classpower = true, preview = false })
    end)
    Case("quiesce:pending", function()
        service.RequestUnit("player", "oracle", { text = true, notify = false, preview = false })
        return service.Quiesce(false)
    end)
    Case("combat:deferred", function()
        -- Isolate the Apply service's deferred queue from unrelated client event owners.
        world.widgets.inCombat = true
        service.RequestUnit("player", "oracle", { text = true, notify = false, preview = false })
        service.Quiesce(true)
        service.Flush()
        assert(#trace == 0, "deferred queue invoked runtime owners during combat")
        world.widgets.inCombat = false
        service.Quiesce(false)
        return true
    end)
end

assert(cases == 980 and checksum == 625020356, "legacy apply traces differ from a6bea101")
print("PASS legacy apply oracle: " .. cases .. " exact baseline routing traces")
