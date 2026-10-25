-- <root> [baseline directory or -] [measure|plain|providers] [client].
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local baseline = arg[2] and arg[2] ~= "-" and arg[2] or nil
local mode = arg[3]
local function Read(relative)
    local f = assert(io.open((baseline or root) .. "/" .. relative, "rb"))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local failures = {}
local function Check(ok, message) if not ok then failures[#failures + 1] = message end end
local path = "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"
local source = Read(path)
local a, b = assert(source:find("local function PlainNumber(value)", 1, true)), assert(source:find("\nUtils.Castbar_PlainNumber", 1, true))
local plain, secret, convert, calls = nil, {}, false, 0
local env = setmetatable({ toPlainHuge = math.huge, toPlainIsSecret = function(v) return v == secret end,
    ToPlain = function(value) calls = calls + 1; if convert then return plain end end }, { __index = _G })
local chunk = assert(loadstring(source:sub(a, b - 1) .. "\nreturn PlainNumber", "@" .. root .. "/" .. path))
setfenv(chunk, env)
local number = chunk()

if mode == "measure" then
    local vm, calls = 0, 0
    debug.sethook(function(event)
        if debug.getinfo(2, "S").source:find("MSUF_CastbarUtils.lua", 1, true) then
            if event == "count" then vm = vm + 1 else calls = calls + 1 end
        end
    end, "c", 1)
    number(12.5)
    debug.sethook()
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 10000 do number(12.5) end
        minimum = math.min(minimum, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    print(string.format("PlainNumber direct: %d VM, %d addon calls, %.3f KB/10000", vm, calls, minimum))
end
if mode ~= "providers" and mode ~= "measure" then
    for _, text in ipairs({ "nan", "inf", "-inf", "1e999", "-1e999" }) do
        convert = false
        Check(number(text) == nil, "raw string accepted nonfinite " .. text)
        convert, plain = true, text
        Check(number({}) == nil, "ToPlain string accepted nonfinite " .. text)
        plain = setmetatable({}, { __tostring = function() return text end })
        Check(number({}) == nil, "ToPlain wrapper accepted nonfinite " .. text)
    end
    convert, plain = true, secret
    Check(number(secret) == nil and number({}) == nil, "secret entered conversion")
    convert, plain, calls = false, nil, 0
    for _ = 1, 100 do assert(number(12.5) == 12.5) end
    assert(calls == 0, "direct numeric path calls ToPlain")
    Check(number("12.5") == 12.5, "finite string changed")
    convert, plain = true, setmetatable({}, { __tostring = function() return "12.5" end })
    Check(number({}) == 12.5, "finite wrapper changed")
end
if mode ~= "plain" then
    local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
    local clients = arg[4] and { arg[4] } or { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }
    for _, flavor in ipairs(clients) do
        local world = World.New(root, { budget = true, flavor = flavor })
        local ns, bars = world.core, world.core.Castbars
        ns.Require("MSUF_EnsureDB", "interrupt sweep")(true)
        ns.Require("MSUF_Castbars_OnSettingsChanged", "interrupt sweep")()
        world:Advance(.5)
        world.secretCasts = false
        local function Load(name)
            local file = "MidnightSimpleUnitFrames/Castbars/" .. name
            local fn = assert(loadstring(Read(file), "@" .. root .. "/" .. file))
            setfenv(fn, world.env)
            fn("MidnightSimpleUnitFrames", ns)
        end
        Load("MSUF_CastbarDriver.lua")
        Load("MSUF_PlayerCastbarRuntime.lua")
        local target, player = bars.Frames.Get("target"), bars.Frames.Get("player")
        player:SetScript("OnEvent", bars.Player.PlayerCastbar_OnEvent)
        world.env.MSUF_DB.player.showInterrupt, world.env.MSUF_DB.target.showInterrupt = true, true
        bars.Config.Invalidate()
        target = bars.Driver.CreateCastBar("MSUF_InterruptSweepTarget", "target")
        world:StartCast("player", "Interrupt test", 600, 531)
        local function Player()
            world:Fire(player, "UNIT_SPELLCAST_START", "player", nil, nil, 531)
            world:Fire(player, "UNIT_SPELLCAST_INTERRUPTED", "player", nil, nil, nil, 531)
            assert(player.interruptFeedbackEndTime, "real player interrupt did not run")
        end
        local function Target() target:SetInterrupted(); assert(target.interrupted, "real target interrupt did not run") end
        if mode == "measure" then
            for label, operation in pairs({ player = Player, target = Target }) do
                for _ = 1, 25 do operation() end
                local vm = world:AddonInstructions(operation)
                local calls, native, counts = 0, 0, {}
                debug.sethook(function()
                    if debug.getinfo(2, "S").source:find("MidnightSimpleUnitFrames/", 1, true) then calls = calls + 1 end
                end, "c")
                operation()
                debug.sethook()
                for key,value in pairs(world.counts) do counts[key] = value end
                operation()
                for key,value in pairs(world.counts) do native = native + value - (counts[key] or 0) end
                local minimum = math.huge
                for _ = 1, 2 do
                    collectgarbage("collect")
                    for _ = 1, 25 do operation() end
                    collectgarbage("stop")
                    local kb = collectgarbage("count")
                    for _ = 1, 100 do operation() end
                    minimum = math.min(minimum, collectgarbage("count") - kb)
                    collectgarbage("restart")
                end
                print(string.format("%s %s interrupt: %d VM, %d addon calls, %d counted natives, %.3f KB/100",
                    flavor, label, vm, calls, native, minimum))
            end
        else
            for _, spec in ipairs({ { "MSUF_CastbarDriver.lua", Target }, { "MSUF_PlayerCastbarRuntime.lua", Player } }) do
                local duration = bars.Utils.GetInterruptFeedbackDuration
                bars.Utils.GetInterruptFeedbackDuration = function() error("interrupt consumer re-read provider") end
                local ok = pcall(spec[2])
                bars.Utils.GetInterruptFeedbackDuration = duration
                Check(ok, flavor .. " " .. spec[1] .. " re-read feedback provider")
                if spec[1] == "MSUF_PlayerCastbarRuntime.lua" then
                    world:Fire(player, "UNIT_SPELLCAST_START", "player", nil, nil, 531)
                    local reverse = bars.Utils.GetReverseFillSafe
                    bars.Utils.GetReverseFillSafe = function() error("interrupt consumer re-read direction provider") end
                    local ok = pcall(world.Fire, world, player, "UNIT_SPELLCAST_INTERRUPTED", "player", nil, nil, nil, 531)
                    bars.Utils.GetReverseFillSafe = reverse
                    Check(ok, flavor .. " player re-read direction provider")
                    bars.Utils.GetReverseFillSafe = nil
                    local loaded, why = pcall(Load, spec[1])
                    bars.Utils.GetReverseFillSafe = reverse
                    Check(not loaded and tostring(why):find("GetReverseFillSafe", 1, true), flavor .. " accepted absent direction provider")
                end
                for _, entry in ipairs({ { bars.Utils, "GetInterruptFeedbackDuration" }, { bars.Runtime, "ApplyInterruptValues" } }) do
                    local saved = entry[1][entry[2]]
                    for _, invalid in ipairs({ false, true, 42, "bad", {} }) do
                        entry[1][entry[2]] = invalid
                        local loaded, why = pcall(Load, spec[1])
                        Check(not loaded and tostring(why):find(entry[2], 1, true), flavor .. " accepted invalid " .. entry[2])
                    end
                    entry[1][entry[2]] = nil
                    local loaded, why = pcall(Load, spec[1])
                    Check(not loaded and tostring(why):find(entry[2], 1, true), flavor .. " accepted absent " .. entry[2])
                    entry[1][entry[2]] = saved
                end
                Load(spec[1])
            end
        end
    end
end
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS castbar_finite_interrupt_providers")
