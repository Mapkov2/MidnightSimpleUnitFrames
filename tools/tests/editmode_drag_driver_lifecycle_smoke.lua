-- All drag kinds share a dormant ticker, including cold Options-unloaded entry.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checks = 0
local function Check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
local function Visibility(frame, shown)
    frame:SetShown(shown)
    local handler = frame:GetScript(shown and "OnShow" or "OnHide")
    if handler then handler(frame) end
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    for _, optionsLoaded in ipairs({ true, false }) do
        local world = World.New(root, flavor)
        local errors = {}
        world.env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
        world.env.secureexecuterange = function(list, callback, ...)
            for i = 1, #list do
                local ok, message = pcall(callback, i, list[i], ...)
                if not ok then world.env.geterrorhandler()(message) end
            end
        end
        if optionsLoaded then
            world:Boot()
        else
            local suffix = world.client.tocSuffix or flavor
            world:LoadGraph("MidnightSimpleUnitFrames",
                World.Graph(root, World.CoreTOC(suffix), "enUS", world.client.isForever and "camelot" or nil), world.core)
        end
        Check(world:FirstFailure() == nil, flavor .. ": graph did not boot")
        local ns, env = world.core, world.env
        local kinds, driver = ns.EditModeKinds, ns.EditModeDragDriver
        local shared = driver.GetFrame()
        Check(not shared:GetScript("OnUpdate") and not shared:IsShown(), "driver did work while idle")
        for _, name in ipairs({ "unit", "stacked", "castbar", "subframe", "group", "aura", "external", "gameplay" }) do
            for _, method in ipairs({ "bounds", "beginDrag", "applyDrag", "commit", "history", "openPopup" }) do
                Check(type(kinds[name][method]) == "function", name .. ": missing strategy " .. method)
            end
        end
        Check(env.MSUF_EM2.ExternalProviders.Shared.CASTBAR_FIELDS == ns.Castbars.UNIT_CASTBAR, "castbar schema copied")
        local first, second, later = env.CreateFrame("Frame"), env.CreateFrame("Frame"), env.CreateFrame("Frame")
        first:Show()
        second:Show()
        later:Show()
        local counts = { first = 0, second = 0, later = 0 }
        kinds.Attach("aura", first, function() counts.first = counts.first + 1 end)
        env.MSUF_EM2.Ticker.Start()
        Check(shared:IsShown() and shared:GetScript("OnUpdate"), "native Start hid an existing hosted drag")
        local mutate = true
        kinds.Attach("gameplay", second, function()
            counts.second = counts.second + 1
            if mutate then
                mutate = false
                kinds.Detach(first)
                kinds.Attach("castbar", later, function() counts.later = counts.later + 1 end)
            end
        end)
        Check(not first:GetScript("OnUpdate") and not second:GetScript("OnUpdate"), "an owner kept a private ticker")
        shared:GetScript("OnUpdate")(shared, 0.016)
        Check(counts.first == 1 and counts.second == 1 and counts.later == 0, "subscription mutation changed the running tick")
        shared:GetScript("OnUpdate")(shared, 0.016)
        Check(counts.first == 1 and counts.second == 2 and counts.later == 1, "shared driver lost a strategy")
        Visibility(later, false)
        shared:GetScript("OnUpdate")(shared, 0.016)
        Check(counts.later == 1, "hidden drag owner ran a callback")
        Visibility(second, false)
        Check(not shared:GetScript("OnUpdate") and not shared:IsShown(), "all hidden owners left a ticker running")
        Visibility(second, true)
        Check(shared:GetScript("OnUpdate") and shared:IsShown(), "shown owner did not resume its ticker")
        env.MSUF_EM2.Ticker.Stop()
        Check(not driver.IsRunning() and not shared:IsShown() and not shared:GetScript("OnUpdate"), "exit left drag work running")
        local afterError = 0
        driver.Attach(first, function() error("two-owner drag") end)
        driver.Attach(second, function() afterError = afterError + 1 end)
        shared:GetScript("OnUpdate")(shared, .016)
        Check(afterError == 1, "two-owner raising callback aborted later owner")
        driver.Clear()
        for broken = 1, 3 do
            local order = {}
            for i, owner in ipairs({ first, second, later }) do
                Visibility(owner, true)
                driver.Attach(owner, function()
                    order[#order + 1] = i
                    if i == broken then error("drag-owner-" .. i) end
                end)
            end
            local before = #errors
            local ok = pcall(shared:GetScript("OnUpdate"), shared, .016)
            Check(ok and table.concat(order, ",") == "1,2,3", "raising drag owner aborted later owners")
            Check(#errors == before + 1 and errors[#errors]:find("drag-owner-" .. broken, 1, true),
                "drag error not reported once: " .. before .. " -> " .. #errors .. ": " .. tostring(errors[#errors]))
            driver.Clear()
        end
        local order = {}
        driver.Attach(first, function()
            order[#order + 1] = "first"
            driver.Detach(second)
            driver.Attach(later, function() order[#order + 1] = "replacement" end)
            driver.Detach(first)
            error("removing owner")
        end)
        driver.Attach(second, function() order[#order + 1] = "removed" end)
        driver.Attach(later, function() order[#order + 1] = "old" end)
        shared:GetScript("OnUpdate")(shared, .016)
        Check(table.concat(order, ",") == "first", "removed/replaced owners ran on the old tick")
        shared:GetScript("OnUpdate")(shared, .016)
        Check(table.concat(order, ",") == "first,replacement", "replacement missed next tick after error")
        driver.Clear()
        local nativeCalls = {}
        for _, method in ipairs({ "IsVisible", "SetScript", "Show", "Hide" }) do
            local old = shared[method]
            shared[method] = function(self, ...)
                nativeCalls[method] = (nativeCalls[method] or 0) + 1
                return old(self, ...)
            end
        end
        driver.Attach(shared, function() end)
        nativeCalls = {}
        for _ = 1, 100 do shared:GetScript("OnUpdate")(shared, .016) end
        Check(nativeCalls.IsVisible == 100 and not nativeCalls.SetScript and not nativeCalls.Show and not nativeCalls.Hide,
            "steady drag changed native visibility/frame-write work")
        driver.Clear()
        driver.Attach(first, function() driver.Clear(); error("clear during drag") end)
        driver.Attach(second, function() error("phantom drag") end)
        shared:GetScript("OnUpdate")(shared, .016)
        Check(not driver.IsRunning(), "raising cleanup left a phantom active drag")
        driver.Attach(first, function() end)
        -- Parent visibility can change without the owner's OnHide firing.
        first.shown = false
        shared:GetScript("OnUpdate")(shared, .016)
        Check(not driver.IsRunning(), "parent-hidden owner left idle work running")
        driver.Clear()
        Check(optionsLoaded or world.optionsPaths == nil, "driver loaded Options")
    end
end
print("PASS shared Edit Mode drag driver: " .. checks .. " checks, eight kinds, five clients, both Options states")
