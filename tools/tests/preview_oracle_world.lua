-- Adapters call the real preview builders and refreshers. They contain no painting rules.
local Adapter = {}

local STOCK_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 }, DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, MONK = { r = 0, g = 1, b = 0.6 },
    DRUID = { r = 1, g = 0.49, b = 0.04 }, DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER = { r = 0.2, g = 0.58, b = 0.5 },
}

function Adapter.Open(root, flavor, Regions)
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    return MenuWorld.Open(root, flavor, { open = false, beforeCore = function(world)
        Regions.Install(world)
        world.env.RAID_CLASS_COLORS = STOCK_COLORS
        world.env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        world.env.CLASS_ICON_TCOORDS = {}
        for index, class in ipairs({ "WARRIOR", "MAGE", "ROGUE", "DRUID", "HUNTER", "SHAMAN", "PRIEST",
            "WARLOCK", "PALADIN", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }) do
            local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
            world.env.CLASS_ICON_TCOORDS[class] = { column / 4, (column + 1) / 4, row / 4, (row + 1) / 4 }
        end
    end })
end

local function Source(root, fn)
    return debug.getinfo(fn, "S").source:gsub("^@", ""):gsub("\\", "/"):sub(#root + 2)
end

local function Hosts(aliases, region, prefix)
    while region do
        if region.frameName == "UIParent" then return end
        aliases[prefix], region = region, region.parent
        prefix = prefix .. "/parent"
    end
end

local OMIT = { parent = true, children = true, regions = true, __env = true, scripts = true,
    events = true, attributes = true, points = true, masks = true }

-- Legacy renderers parent several visual layers beside the body (on the canvas).
-- Select their actual owned regions, without pulling the canvas toolbar/handles into a scene.
local function VisualRoots(owner, path, roots, seen, depth, Regions)
    if seen[owner] or depth > 3 then return end
    seen[owner] = true
    for _, key in ipairs(Regions.Keys(owner)) do
        local value = owner[key]
        if not OMIT[key] and Regions.OwnedField(key) and type(value) == "table" then
            local role = path .. "/" .. tostring(key)
            if rawget(value, "objectType") then
                if not seen[value] then
                    roots[role], seen[value] = value, true
                end
            elseif getmetatable(value) == nil then
                VisualRoots(value, role, roots, seen, depth + 1, Regions)
            end
        end
    end
end

local function Unit(mw, case, Regions)
    local env, Preview = mw.env, mw.core.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return case.unit end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show()
    box.canvas:SetSize(400, 200)
    if case.resource then mw.M.activeKey = "classpower" end
    if case.status then Preview.statusPreviewMode = case.status end
    if case.hidden then
        box.layerVisibility = { power = false, portrait = false, castbar = false, auras = false,
            classPower = false, classPowerText = false, nameText = false, hpText = false, powerText = false, status = false }
    end
    Preview.Refresh(box, "PREVIEW_RENDER_ORACLE")
    assert(box.key == case.unit and box._msufPreviewScene.complete, "unit preview did not render selected unit")
    if case.style == "portrait" then
        assert(box.mock.portrait:IsShown(), "portrait input did not enable actual portrait")
        assert(box._msufPreviewScene.runtimeText.healthColorByHealth, "gradient input did not reach compiled text")
    end
    if case.resource then assert(box.mock.classPower:IsShown(), "resource input did not enable actual CP regions") end
    if case.animated then
        local action = assert(box.animateCombatButton._msuf2CommandAction)
        assert(action.set(true), "animation toggle failed")
        box:GetScript("OnUpdate")(box, 0.06)
        mw.world.widgets:SetTime(101.25)
        box:GetScript("OnUpdate")(box, 0.06)
    end
    local aliases = {}
    Hosts(aliases, box.canvas, "canvas")
    local roots = { unit = box.mock }
    VisualRoots(box.mock, "unit", roots, {}, 0, Regions)
    if box.auraPreviewVisuals then VisualRoots(box.auraPreviewVisuals, "auras", roots, {}, 0, Regions) end
    return roots, aliases, { build = Source(mw.world.root, Preview._BuildPreview),
        render = Source(mw.world.root, Preview.Refresh), entry = "UFPreview._BuildPreview; UFPreview.Refresh",
        animation = case.animated and "animateCombatButton action; OnUpdate(0.06) at 101.25" or nil }
end

local function Group(mw, case)
    mw.M.SetMenuStateValue("gfScope", case.scope)
    assert(mw.M.Open("gf_auras") ~= false, "group page did not open")
    mw:RunTimers()
    local box
    for _, candidate in ipairs(mw.M._gfNativePreviews or {}) do
        if candidate:IsShown() then assert(not box, "ambiguous active group preview") box = candidate end
    end
    assert(box and box._mock, "group preview missing")
    if case.hidden then
        for _, key in ipairs({ "power", "portrait", "buff", "debuff", "trackedBuff", "external", "text", "status" }) do
            mw.M.gfPreviewLayerVisible[key] = false
        end
    end
    box:Refresh("PREVIEW_RENDER_ORACLE")
    if case.style == "portrait" then
        assert(box._mock._msufGroupPortrait and box._mock._msufGroupPortrait:IsShown(), "group portrait did not render")
    end
    local aliases = {}
    aliases.group = box._mock
    Hosts(aliases, box._stage.parent, "host")
    return { canvas = box._stage }, aliases, { render = Source(mw.world.root, box.Refresh),
        entry = "SetMenuStateValue(gfScope); Open(gf_auras); native preview box:Refresh" }
end

local function Castbar(mw, case)
    assert(mw.M.Open("opt_castbar") ~= false, "castbar page did not open")
    mw:RunTimers()
    assert(mw.M.SetCastbarPreviewUnit(case.unit), "castbar unit selection failed")
    assert(mw.M.SetCastbarPreviewType(case.castType, case.progress), "castbar type selection failed")
    mw:RunTimers()
    local preview = assert(mw.M._msuf2CastbarPreview)
    mw.world.widgets:SetTime(100)
    preview:Refresh()
    if case.interrupted then assert(mw.M.PlayCastbarPreviewInterrupt(), "interrupt action failed") end
    local aliases = {}
    local used = { [preview.castRow] = true }
    for _, key in ipairs({ "bar", "icon", "iconTexture", "iconOutlineFrame", "outlineFrame", "statusBar", "fill",
        "barBg", "castText", "time", "castTargetText", "textLayer", "spark", "latency", "kick" }) do
        local region = preview[key]
        if region and not used[region] then aliases["castbar/" .. key], used[region] = region, true end
    end
    for _, key in ipairs({ "ticks", "stageTicks", "empowerBands", "empowerFills" }) do
        for index, region in ipairs(preview[key] or {}) do
            if not used[region] then aliases["castbar/" .. key .. "/" .. index], used[region] = region, true end
        end
    end
    Hosts(aliases, preview.castRow.parent, "host")
    return { castbar = preview.castRow }, aliases, { render = Source(mw.world.root, preview.Refresh),
        entry = "Open(opt_castbar); SetCastbarPreviewUnit; SetCastbarPreviewType; preview:Refresh; optional interrupt" }
end

local function ClassPower(mw, case)
    assert(mw.M.Open("classpower") ~= false, "class resource page did not open")
    mw:RunTimers()
    local workspace = assert(mw.M.ClassPowerWorkspace.current)
    workspace:Select("class")
    local box = assert(workspace.page.ctx.entry.classPowerPreview)
    mw.M._msuf2ClassPowerPreviewSpecKey = case.resource
    assert(mw.M.ClassPowerPreviewSpecs[case.resource], "selected resource unsupported")
    if case.hidden then box.layerVisibility = { class = false, classText = false, power = false, hp = false } end
    box:Refresh()
    assert(box._msufCPPreviewAnim.spec.key == case.resource, "class resource selection did not reach renderer")
    local aliases = {}
    aliases["resources/class"], aliases["resources/power"] = box.classPower, box.detachedPower
    aliases["resources/health"], aliases["resources/reference"] = box.playerHP, box.playerRef
    Hosts(aliases, box.stage.parent, "host")
    return { resources = box.stage }, aliases, { render = Source(mw.world.root, box.Refresh),
        entry = "Open(classpower); ClassPowerWorkspace:Select(class); classPowerPreview:Refresh" }
end

local PAINTERS = { unit = Unit, group = Group, castbar = Castbar, classpower = ClassPower }

function Adapter.Render(root, flavor, case, Regions, Cases)
    math.randomseed(1701)
    local mw = Adapter.Open(root, flavor, Regions)
    Cases.Configure(mw, case)
    local roots, aliases, provenance = assert(PAINTERS[case.surface])(mw, case, Regions)
    return mw, roots, aliases, provenance
end

return Adapter
