-- Every composed owner rejects a missing dependency before publishing its stages.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local Open = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open
local captured = {}
local contracts = {
    UnitLayout = { "Stage", "Shared" },
    UnitPresentation = { "Stage", "Shared" },
    Auras = { "Runtime", "Scene" },
    GroupPlan = { "Runtime", "Scene" },
    GroupPresentation = { "Runtime", "Layout", "Layers" },
}
local fields = {
    UnitLayout = { Stage = "", Shared = "AnimatedPreviewData PreviewLayerWanted RefillTable BodyAliases StatusRegions Empty" },
    UnitPresentation = { Stage = "", Shared = "PreviewLayerWanted ClassPowerWidth" },
    Auras = { Runtime = "Core Menu Wipe Max", Scene = "Stage" },
    GroupPlan = { Runtime = "Exports Wipe",
        Scene = "AuraLanes BuildAuraLanes BuildSpells StatusAvailable AuraAvailable AuraTextAvailable SampleLayerSections" },
    GroupPresentation = { Runtime = "Menu", Layout = "SetFrameLevel TextHandleKeys TextSlotHandleKeys AuraLanes",
        Layers = "IsOn Alpha StatusAvailable" },
}
local function Watch(owner, key, name)
    local factory = assert(owner[key], "missing owner " .. name)
    owner[key] = function(...)
        assert(not captured[name], "owner rebound during menu boot: " .. name)
        captured[name] = { factory = factory, args = { ... }, count = select("#", ...) }
        return factory(...)
    end
end
local mw = Open(root, "Mainline", { open = false, beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_UnitPreview_Render.lua$") then
            Watch(ns.UFPreviewLayout, "Install", "UnitLayout")
            Watch(ns.UFPreviewPresentation, "Install", "UnitPresentation")
        elseif path:match("MSUF_Menu2_GroupPreview_Render.lua$") then
            local factories = ns.MSUF2.GroupRenderFactories
            Watch(factories, "Auras", "Auras")
            Watch(factories, "Plan", "GroupPlan")
            Watch(factories, "Presentation", "GroupPresentation")
        end
        return load(self, path, addon, ns)
    end
end })
local checks = 0
for name, domains in pairs(contracts) do
    local record = assert(captured[name], "owner was not composed: " .. name)
    assert(record.count == #domains, "unexpected owner arity: " .. name)
    for index, domainName in ipairs(domains) do
        local domain, prefix = record.args[index], name .. "." .. domainName
        for _, invalid in ipairs({ false, "missing" }) do
            if invalid == "missing" then record.args[index] = nil else record.args[index] = false end
            local ok, why = pcall(record.factory, unpack(record.args, 1, record.count))
            record.args[index] = domain
            assert(not ok and tostring(why):find(prefix .. " interface is required", 1, true), prefix .. " was not required")
            checks = checks + 1
        end
        local required = {}
        for key in fields[name][domainName]:gmatch("%S+") do
            required[key] = true
            local value = assert(domain[key], prefix .. "." .. key .. " was not supplied")
            domain[key] = nil
            local ok, why = pcall(record.factory, unpack(record.args, 1, record.count))
            domain[key] = value
            assert(not ok and tostring(why):find(prefix .. "." .. key .. " is required", 1, true), prefix .. "." .. key)
            checks = checks + 1
        end
        -- Stage is an output table filled by its owner, not a dependency bag.
        if domainName ~= "Stage" then
            for key in pairs(domain) do assert(required[key], prefix .. "." .. key .. " lacks a dependency test") end
        end
    end
end
local selection = mw.core.UFPreviewSelection
for key in ("SelectHandle RefreshVisuals ReadOffsets WriteOffsets NudgeSelected StatusRefresh GearOptions"):gmatch("%S+") do
    local value = assert(selection[key])
    selection[key] = nil
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Input.lua"))
    setfenv(chunk, mw.env)
    local ok, why = pcall(chunk, "Options", mw.core)
    selection[key] = value
    assert(not ok and tostring(why):find("UnitInput.Selection." .. key .. " is required", 1, true), "input dependency " .. key)
    checks = checks + 1
end
-- Native assembly passes separate required domains to the two consumers.
local groupOwners = {
    { name = "GroupHandles", api = mw.M.GroupPreviewHandles, depsAt = 2,
      domains = {
        Config = "Round ResolveAnchor PointOffset HandleOffset CurrentStatusSpec CurrentSpellConfig StatusLabel OffsetToConfig",
        Selection = "HandleText HandleOffsets RefreshHandleSelection Helpers OpenGFSection",
        Interaction = "StartPan StopPan ZoomWheel",
      } },
    { name = "GroupRender", api = mw.M.GroupPreviewRender, depsAt = 3,
      domains = {
        Config = "GF_PREVIEW_ROLE_DEFAULT StatusSpecs ScaleValue ConfigToOffset CompiledSpec CompiledAuraLane RuntimeStatusConfig "
            .. "CurrentStatusSpec StatusSpecEnabled StatusSpecInMode StatusSpecIsText StatusText StatusLabel CurrentSpellInfo "
            .. "PreviewAllSpecSpellIcons CurrentSpellConfig CurrentSpellPlaced CurrentSpellTexture CurrentSpellColor MockSpellTexture "
            .. "Round ClampLayer ClassColor AuraGrowth Int",
        Selection = "RefreshHandleSelection Helpers",
        Interaction = "ResolveDefaultZoomLock UpdateZoomControls ClampZoom",
        Handles = "statusHandles SelectHandle NudgeHandlePosition",
      } },
}
for _, owner in ipairs(groupOwners) do
    owner.factory = owner.api.Install
    owner.api.Install = function(...)
        owner.args = { ... }
        return owner.factory(...)
    end
end
local box = mw.M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = "gf_layout" })
for _, owner in ipairs(groupOwners) do
    owner.api.Install = owner.factory
    local args = assert(owner.args, owner.name .. " was not composed")
    local deps = args[owner.depsAt]
    for domainName, words in pairs(owner.domains) do
        local domain = assert(deps[domainName])
        local prefix = owner.name .. "." .. domainName
        deps[domainName] = nil
        local ok, why = pcall(owner.factory, unpack(args))
        deps[domainName] = domain
        assert(not ok and tostring(why):find(prefix .. " interface is required", 1, true), prefix)
        checks = checks + 1
        for key in words:gmatch("%S+") do
            local value = assert(domain[key], prefix .. "." .. key)
            domain[key] = nil
            ok, why = pcall(owner.factory, unpack(args))
            domain[key] = value
            assert(not ok and tostring(why):find(prefix .. "." .. key .. " is required", 1, true), prefix .. "." .. key)
            checks = checks + 1
        end
    end
end
box:Hide()
print("PASS preview owner contracts: " .. checks .. " required domain/field cases")
