-- <root> [client]: actual ScanHeader -> ApplyButton -> ApplySpec -> element Apply.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    h.env.AbbreviateNumbers = tostring
    h.env.AbbreviateLargeNumbers = tostring
    h.env.BreakUpLargeNumbers = tostring
    if arg[3] then
        local loadFile = h.world.LoadFile
        function h.world:LoadFile(path, addon, namespace)
            local file = io.open(arg[3] .. "/" .. path:match("[^/]+$"), "rb")
            if not file then return loadFile(self, path, addon, namespace) end
            local source = file:read("*a")
            file:close()
            local chunk = assert(loadstring(source, "@" .. path))
            setfenv(chunk, self.env)
            return pcall(chunk, addon, namespace)
        end
    end
    local load = h.world.LoadGraph
    function h.world:LoadGraph(addon, ...)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
    end
end })
local GF, UF = h.GF, h.UF
GF.GetConf("raid").enabled = true
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local frame = assert(GF.FrameForUnit("raid4"))
local shell = frame._msufSecureShell or frame
local health = assert(UF.elements.Health)
local apply, attempts, fail = assert(health.Apply), 0, false
health.Apply = function(owner, ...)
    if owner == frame then
        attempts = attempts + 1
        if fail then error("injected element Apply") end
    end
    return apply(owner, ...)
end
local reports, throwing = 0, false
h.env.geterrorhandler = function() return function(message)
    reports = reports + 1
    assert(message:find("injected", 1, true), message)
    if throwing then error("injected reporter") end
end end
local function Flags(held)
    assert(UF._msufApplyingSpec == held and frame._msufElementApplyBatch == nil, "apply flags leaked")
end
for _, held in ipairs({ "nil", "false", "true" }) do
    local old
    if held == "false" then old = false elseif held == "true" then old = true end
    UF._msufApplyingSpec = old
    -- Only the first scan changes the spec serial; the retry is unchanged.
    GF.InvalidateCompiledSpecs("raid")
    fail = true
    assert(GF.ScanHeader("raid", "raid") == false, "partial header scan recorded success")
    Flags(old)
    assert(frame._msufElementApplyFailed == true and attempts > 0, "real element fault was bypassed")
    local before = attempts
    fail = false
    GF.ScanHeader("raid", "raid")
    Flags(old)
    assert(attempts == before + 1 and frame._msufElementApplyFailed == nil,
        "unchanged header retry skipped the failed real ApplyButton")
    before = attempts
    GF.ScanHeader("raid", "raid")
    assert(attempts == before, "successful unchanged frame lost SameApplied")
    -- An already successful signature cannot hide a later targeted failure.
    fail = true
    assert(GF.ApplyStructureSpec(frame, frame.MSUFSpec) == false, "structure layer recorded failure as success")
    assert(GF.ApplyButton(shell, "raid") == false, "button layer recorded failure as success")
    Flags(old)
    fail = false
    assert(GF.ApplyButton(shell, "raid") == true and not frame._msufElementApplyFailed, "direct retry failed")
    UF._msufApplyingSpec = nil
end
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if name == nil then break end
    end
    error("missing upvalue " .. wanted)
end
local applyOne = Upvalue(UF.Factory.Apply, "ApplyOne")
local config = Upvalue(UF.Factory.Apply, "ResolveConfig")(false)
local target = h.env.CreateFrame("Button", "L2Target", h.env.UIParent)
target.MSUFUnitKey = "target"
target._msufVisibilityManaged = true
UF.AttachFrame(target, { scope = "single" })
UF.frames.target = target
local variantOff = target._msufVariantOff
health.Apply = function(owner, ...)
    if owner == target and fail then error("injected single element Apply") end
    return apply(owner, ...)
end
target._msufVariantOff, fail = true, true
assert(applyOne("target", config, true) == false, "single-frame factory recorded failure as success")
assert(target._msufVariantOff == true and target._msufElementApplyFailed == true, "single-frame failure committed success")
fail = false
assert(applyOne("target", config, true) == true and not target._msufElementApplyFailed, "single-frame retry failed")
target._msufVariantOff = variantOff
health.Apply = apply
-- Real teardown faults and nesting; ApplyButton is never replaced.
local header = assert(GF.headers.raid)
local auras = h.core.MSUF_Auras3
for _, phase in ipairs({ "children", "aura-end", "driver", "nested", "element" }) do
    for _, raises in ipairs({ false, true }) do
        local children, sync = header.GetChildren, UF.SyncRuntimeDriver
        local auraEnd = auras and auras.EndTopologyBatch
        local beforeReports, fault, nested = reports, true, false
        throwing = raises
        if phase == "children" then
            header.GetChildren = function(self)
                if fault then error("injected children") end
                return children(self)
            end
        elseif phase == "driver" then
            UF.SyncRuntimeDriver = function(...)
                if fault then error("injected driver") end
                return sync(...)
            end
        elseif phase == "aura-end" and auraEnd then
            auras.EndTopologyBatch = function(...)
                auraEnd(...)
                if fault then error("injected aura-end") end
            end
        else
            health.Apply = function(owner, ...)
                if owner == frame and fault then
                    if phase == "nested" and not nested then
                        nested = true
                        fault = false
                        assert(GF.ScanHeader("raid", "raid"))
                        fault = true
                        assert(UF._msufApplyingSpec == true, "inner scan cleared outer batch")
                    end
                    error("injected element Apply")
                end
                return apply(owner, ...)
            end
            GF.InvalidateCompiledSpecs("raid")
        end
        local ok, message = pcall(GF.ScanHeader, "raid", "raid")
        Flags(nil)
        if phase ~= "aura-end" or auraEnd then
            assert(reports > beforeReports, phase .. " was not reported")
            if raises then assert(not ok and tostring(message):find("injected reporter", 1, true)) end
        end
        fault, throwing = false, false
        header.GetChildren, UF.SyncRuntimeDriver = children, sync
        if auras then auras.EndTopologyBatch = auraEnd end
        health.Apply = apply
        assert(GF.ScanHeader("raid", "raid"), "failed scan prevented a normal retry")
        Flags(nil)
    end
end
-- The scene wrapper shares the same success contract as live ApplyButton.
local sceneRoot = GF.NewPreviewScene(h.env.UIParent)
sceneRoot:Activate()
local scene = sceneRoot:Group("raid", 1)
scene:Show(1, { immediate = true })
local sample = assert(scene.t.frames.raid[1])
local sceneApply = health.SceneApply
health.SceneApply = function() error("injected scene Apply") end
local rebinds = 0
debug.sethook(function(event)
    if event == "call" and debug.getinfo(2, "f").func == GF.RebindGroupHotRuntime then rebinds = rebinds + 1 end
end, "c")
local sceneOK = GF.ApplySceneButton(sample, "raid")
debug.sethook()
assert(sceneOK == false and rebinds == 0, "scene wrapper recorded failure as success")
health.SceneApply = sceneApply
assert(GF.ApplySceneButton(sample, "raid") == true, "scene retry failed")
assert(reports > 0 and #h.violations == 0, "missing reports or protected writes")
print("PASS uf_header_scan_transaction " .. flavor .. ": real button/Core/factory failure, unchanged retry, nesting and teardown")
