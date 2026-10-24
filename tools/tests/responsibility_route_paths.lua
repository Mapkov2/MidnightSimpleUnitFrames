-- Public/event routes supplement the unchanged callable-boundary operations.
local Routes = {}
function Routes.New(World, root, flavor, harness, selectedName)
    local Base = dofile(harness .. "/tools/tests/callable_boundary_paths.lua")
    local w, _, _, _, Registry = Base.New(World, root, flavor, harness)
    local e, u = w.env, w.UF
    local cases = {}
    local function Add(name, run, prepare, iterations)
        -- Keep discovery complete; selected worlds still execute every setup statement.
        if selectedName ~= nil and name ~= selectedName then return end
        cases[#cases + 1] = { name = name, run = run, prepare = prepare or function() end,
            iterations = iterations or 10 }
    end
    local lateFrame, lateHandler
    for _, frame in ipairs(w.h.widgets.frames) do
        local fn = frame:GetScript("OnEvent")
        if frame.events.EDIT_MODE_LAYOUTS_UPDATED and fn
            and debug.getinfo(fn, "S").source:find("MSUF_UF_Factory.lua", 1, true) then
            assert(not lateHandler, "duplicate late-anchor owner")
            lateFrame, lateHandler = frame, fn
        end
    end
    assert(lateHandler, "late-anchor event callback absent")
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED" }) do
        Add("factory-event:" .. event, function() return lateHandler(lateFrame, event) end,
            function()
                e.MSUF_DB.general.anchorName = "EssentialCooldownViewer"
            end, 100)
    end
    for _, mode in ipairs({ "ordinary", "inline", "direct", "both" }) do
        Add("target-offset-apply:" .. mode, function()
            for i = 1, 10 do
                e.MSUF_DB.target.nameOffsetX = i % 2
                u.Config.Refresh()
                u.Factory.Apply("target")
            end
        end, function()
            e.MSUF_DB.target.showName = true
            e.MSUF_DB.target.directTextLayout = mode == "direct" or mode == "both"
            e.MSUF_DB.targettarget.showToTInTargetName = mode == "inline" or mode == "both"
            u.frames.target = nil
            e[u.FrameName("target")] = false
        end, 1)
    end
    dofile(harness .. "/tools/tests/responsibility_route_branches.lua")(w, Add, root, harness, lateFrame, lateHandler)
    if selectedName ~= nil then assert(#cases == 1, "route selection is not unique: " .. selectedName) end
    return w, cases, Registry
end
return Routes
