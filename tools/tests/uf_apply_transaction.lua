-- Real cold apply bodies and Kernel boundary. Optional args 2/3 select review fixtures for Core/Kernel.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local path = root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local source = Read(arg[2] or path)
local first = assert(source:find("function UF.ApplyElementToFrame(", 1, true))
local last = assert(source:find("\n--- IsEnabled for a scene frame:", first, true))
local phases = { "spec", "Create", "Apply", "Enable", "Update", "routing", "driver", "after" }
for _, phase in ipairs(phases) do
    for _, held in ipairs({ "nil", "false", "true" }) do
        local old = held == "true" and true or held == "false" and false or nil
        if held == "false" then old = false end
        local failures, rebuilds, syncs, afters, failure = 0, 0, 0, 0, phase
        local throwReporter
        local visits, updates = {}, 0
        local UF = { elements = {}, _msufApplyingSpec = old }
        local frame = { MSUFUnitKey = "target", _msufElementApplyBatch = old,
            _msufEventRouteUnit = "target", _msufElementEventRoutes = {}, _msufPixelLayoutTemplateVisited = true }
        local function Fail(at)
            if failure == at then error("injected " .. at) end
        end
        for _, name in ipairs({ "First", "Second", "Third" }) do
            UF.elements[name] = {
                Create = function() if name == "Second" then Fail("Create") end end,
                Apply = function() visits[name] = (visits[name] or 0) + 1; if name == "Second" then Fail("Apply") end end,
                Enable = function() if name == "Second" then Fail("Enable") end end,
                Update = function() if name == "Second" then Fail("Update") end end,
            }
        end
        UF.ElementEnabled = function() return true end
        UF.SetFrameSpec = function(f, spec) Fail("spec"); f.MSUFSpec = spec end
        UF.AttachFrame = function() end
        UF.FrameRuntimeUpdate = function() updates = updates + 1 end
        UF.SyncRuntimeDriver = function() Fail("driver"); syncs = syncs + 1 end
        local ns = { UF = UF, ExportPublic = function() end }
        local env = setmetatable({
            UF = UF, MSUF = ns, elementOrder = { "First", "Second", "Third" }, scopedElementOrders = {}, Metadata = {},
            PixelLayoutRegion = function() end,
            ApplyElementAllowed = function() return true end,
            FrameDisableElement = function() end,
            SelectElementUpdate = function(element) return element.Update end,
            GetUpdateKey = function(name) return "Update" .. name end,
            RefreshFrameRoutingAfterElementApply = function(f)
                Fail("routing")
                rebuilds = rebuilds + 1
                f._msufEventRouteUnit, f._msufElementEventRoutes = f.MSUFUnitKey, {}
                return true
            end,
            Compiler = { AfterApply = function() Fail("after"); afters = afters + 1 end },
            geterrorhandler = function() return function()
                failures = failures + 1
                if throwReporter then error("injected error reporter") end
            end end,
        }, { __index = _G })
        env._G = env
        local boundary = assert(loadfile(arg[3] or root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
        setfenv(boundary, env)
        boundary("test", ns)
        local chunk = assert(loadstring(source:sub(first, last - 1), "@" .. path))
        setfenv(chunk, env)
        chunk()
        -- Nested batches skip routing/final sync, so test those failures only at the outer level.
        if old ~= true or (phase ~= "routing" and phase ~= "driver") then
            local callOK, applied = pcall(UF.ApplyElementsToFrame, frame, { "First", "Second", "Third" }, {}, "TEST")
            assert(frame._msufElementApplyBatch == old and UF._msufApplyingSpec == old,
                phase .. ": apply flags leaked (" .. held .. ")")
            assert(callOK and applied == false and failures == 1, phase .. ": failure not reported as failed apply")
            assert(frame._msufElementEventRoutes == nil, phase .. ": partial routes remain valid")
            local retriedOK, retried = pcall(UF.ApplyElementsToFrame, frame, { "Second" }, {}, "RETRY_FAIL")
            assert(retriedOK and retried == false and frame._msufElementApplyFailed,
                "a failed retry discarded the full-frame retry marker")
            failure = nil
            visits = {}
            -- A partial request after failure must retry the full frame, including the unvisited tail.
            assert(UF.ApplyElementsToFrame(frame, { "Second" }, {}, "RETRY"))
            assert(visits.First == 1 and visits.Second == 1 and visits.Third == 1, phase .. ": retry was incomplete")
            assert(frame._msufElementApplyBatch == old and UF._msufApplyingSpec == old, "retry flags leaked")
            if old ~= true then assert(rebuilds >= 1 and syncs >= 1, "retry did not rebuild routes/sync driver") end
            if old ~= true and phase ~= "routing" and phase ~= "driver" and phase ~= "after" then
                assert(rebuilds == 1 and syncs == 1, "a successful retry must rebuild/sync exactly once")
            end
            assert(afters == 1 and not frame._msufElementApplyFailed, "retry did not finish/clear failure")
            -- ApplySpec must not issue its runtime update or report success after a partial apply.
            failure = "Apply"
            assert(UF.ApplySpec(frame, {}, "MUST_NOT_UPDATE") == false and updates == 0,
                "ApplySpec hid a partial failure or ran its final runtime update")
            -- Reporting is outside the transaction: even a throwing reporter sees restored flags.
            throwReporter = true
            local reportOK, reportError = pcall(UF.ApplyElementsToFrame, frame, { "Second" }, {}, "REPORT_FAIL")
            assert(not reportOK and tostring(reportError):find("injected error reporter", 1, true))
            assert(frame._msufElementApplyBatch == old and UF._msufApplyingSpec == old,
                "the error reporter observed/leaked transaction flags")
            assert(frame._msufElementEventRoutes == nil and frame._msufElementApplyFailed,
                "the throwing reporter bypassed retry invalidation")
        end
    end
end
print("PASS uf_apply_transaction: eight failure stages; nil/false/nested flags; retry; ApplySpec; throwing reporter")
