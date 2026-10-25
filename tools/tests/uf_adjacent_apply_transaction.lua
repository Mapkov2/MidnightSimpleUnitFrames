-- Execute the real cold scene/detach bodies with the real Kernel boundary.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local file = assert(io.open(arg[2] or path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function Load(first, last, env)
    local chunk = assert(loadstring(source:sub(first, last - 1), "@" .. path))
    setfenv(chunk, env)
    chunk()
end
local detach = source:find("local function RunDetachFrame(", 1, true)
    or assert(source:find("function UF.DetachFrame(", 1, true))
local detachEnd = assert(source:find("\nfunction UF.GetFrame(", detach, true))
local scene = assert(source:find("--- IsEnabled for a scene frame:", 1, true))
local sceneEnd = assert(source:find("\nfunction UF.BeginEventRegistrationBatch(", scene, true))
local cases = 0
for _, mode in ipairs(arg[3] and { arg[3] } or { "scene", "detach" }) do
    local phases = mode == "scene"
        and { "IsEnabled", "SceneIsEnabled", "Create", "Apply", "SceneApply", "Enable", "Disable", "after" }
        or { "Disable", "events", "lifecycle", "driver" }
    for _, phase in ipairs(phases) do
        for _, held in ipairs({ "nil", "false", "true" }) do
            for _, throws in ipairs({ false, true }) do
                if held ~= "true" or phase ~= "driver" then
                    local old = held == "true" and true or nil
                    if held == "false" then old = false end
                    local failure, reports, syncs = phase, 0, 0
                    local frame = { _msufPixelLayoutTemplateVisited = true, MSUFUnitKey = "original",
                        _msufElementApplyBatch = old, _msufActiveElements = { First = true } }
                    local UF = { elements = {}, attachedFrames = { [frame] = true }, attachedFrameList = { frame },
                        _msufApplyingSpec = old }
                    local function Fail(at)
                        if failure == at then error("injected " .. at) end
                    end
                    local function Restored()
                        assert(UF._msufApplyingSpec == old, mode .. "/" .. phase .. ": global apply flag leaked")
                        assert(frame._msufElementApplyBatch == old, "previous element batch flag changed")
                        assert(frame.MSUFUnitKey == "original", "scene enable check leaked its temporary unit key")
                    end
                    local element = {
                        Create = function() Fail("Create") end,
                        Apply = function() Fail("Apply") end,
                        Enable = function() Fail("Enable") end,
                    }
                    if phase == "SceneApply" then element.SceneApply = function() Fail("SceneApply") end end
                    if phase == "SceneIsEnabled" then
                        element.SceneIsEnabled = function() Fail("SceneIsEnabled"); return true end
                    end
                    UF.elements.First = element
                    UF.ElementEnabled = function()
                        assert(frame.MSUFUnitKey == "target", "scene did not use its stand-in unit")
                        Fail("IsEnabled")
                        return failure ~= "Disable"
                    end
                    UF.SyncRuntimeDriver = function() Fail("driver"); syncs = syncs + 1 end
                    local ns = { ExportPublic = function() end }
                    local env = setmetatable({ UF = UF, MSUF = ns, DEFAULT_APPLY_MASK = true,
                        elementOrder = { "First" }, scopedElementOrders = {}, table_remove = table.remove,
                        PixelLayoutRegion = function() end, ApplyElementAllowed = function() return true end,
                        FrameDisableElement = function(f, name)
                            Fail("Disable")
                            f._msufActiveElements[name] = nil
                        end,
                        ClearFrameEvents = function() Fail("events") end,
                        SyncGroupLifecycleDriver = function() Fail("lifecycle") end,
                        Compiler = { AfterApply = function() Fail("after") end },
                        SelectElementUpdate = function() return function() error("scene update ran") end end,
                        GetUpdateKey = function(name) return "Update" .. name end,
                        geterrorhandler = function() return function()
                            Restored()
                            reports = reports + 1
                            if throws then error("injected reporter") end
                        end end,
                    }, { __index = _G })
                    env._G = env
                    local boundary = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
                    setfenv(boundary, env)
                    boundary("test", ns)
                    Load(detach, detachEnd, env)
                    Load(scene, sceneEnd, env)
                    local function Apply()
                        if mode == "scene" then return UF.ApplySceneSpec(frame, {}, true, "single", "target") end
                        return UF.DetachFrame(frame)
                    end
                    local ok, result = pcall(Apply)
                    Restored()
                    assert(reports == 1, "cold transaction did not report its failed step exactly once")
                    if throws then
                        assert(not ok and tostring(result):find("injected reporter", 1, true), "reporter raise was hidden")
                    else
                        assert(ok and result == false, "failed cold transaction did not return false")
                    end
                    failure = nil
                    assert(Apply(), "cold transaction did not recover on the next request")
                    Restored()
                    if mode == "scene" then
                        assert(frame._msufActiveElements.First == true and UF.attachedFrames[frame], "scene retry changed attachment")
                    else
                        assert(not UF.attachedFrames[frame] and #UF.attachedFrameList == 0, "detach retry retained attachment")
                        assert(syncs == (old == true and 0 or 1), "detach driver sync count changed")
                    end
                    cases = cases + 1
                end
            end
        end
    end
end
print("PASS uf_adjacent_apply_transaction: " .. cases .. " scene/detach failure and retry cases")
