local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", arg[3] or "resize"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local surfaces = {}
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world) MenuWorld.InstallNativeUnitInputs(world) end }, arg[4])
local M = mw.M
local checks, width = 0, 1000
M.GetContentMetrics = function() return width, 900 end
M.Theme.ReducedMotionEnabled = function() return true end
local function Check(ok, why)
    checks = checks + 1
    assert(ok, why .. "\n" .. table.concat(mw.world.reported, "\n"))
end
local function Settle()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(1000)
    end
    M.Theme.StopAllMenuAnimations()
end
local function Category(key)
    M.ColorsSetPainterCategory(key)
    Settle()
end
local function SectionSelected(id, expected)
    local section = M.cache.opt_colors.sections[id]
    Check(section ~= nil, "missing section " .. id)
    local parent = section._msuf2CollapsibleEntry and section._msuf2CollapsibleEntry.outer or section
    while parent and parent ~= M.cache.opt_colors.wrapper do
        if not parent:IsShown() then
            Check(not expected, "selected category is hidden: " .. id)
            return
        end
        parent = parent:GetParent()
    end
    Check(expected, "inactive category is still shown: " .. id)
end
local originalSurface = M.PreviewHelpers.NewRuntimeUnitSurface
M.PreviewHelpers.NewRuntimeUnitSurface = function(...)
    local surface = originalSurface(...)
    if mode == "resources" then
        local refresh = surface.Refresh
        function surface:Refresh(sample)
            -- Exercise populated native aura lanes even with factory auras off.
            if sample then sample.auraForceStandard = true end
            return refresh(self, sample)
        end
    end
    surfaces[#surfaces + 1] = surface
    return surface
end
Check(mw:Select("opt_colors") ~= false, "Colors did not open")
Settle()
if mode == "resize" then
    Category("auras")
    width = 1500
    mw.win.maximizeButton:Click()
    Settle()
    Category("accessibility")
    width = 1000
    mw.win.maximizeButton:Click()
    Settle()
    Check(M.colorsPainterCategory == "accessibility", "resize changed selected category")
    SectionSelected("workbench_accessibility", true)
    SectionSelected("colors_auras", false)
    for _, key in ipairs({ "resources", "auras", "accessibility", "unit" }) do
        Category(key)
        local section = ({ resources = "colors_power", auras = "colors_auras",
            accessibility = "workbench_accessibility", unit = "colors_appearance" })[key]
        SectionSelected(section, true)
        width = 1500
        mw.win.maximizeButton:Click()
        Settle()
        SectionSelected(section, true)
        width = 1000
        mw.win.maximizeButton:Click()
        Settle()
        SectionSelected(section, true)
    end
else
    Category("resources")
    local powerSurface = assert(surfaces[#surfaces])
    local frame = assert(powerSurface.scene.frame)
    Check(frame.targetPowerBar:IsShown(), "resource power sample is missing")
    local lanes = 0
    for key, host in pairs(frame._msufGFFrameAuraPreviewHosts or {}) do
        lanes = lanes + 1
        Check(not host:IsShown(), "resource strip leaks aura lane " .. key)
    end
    Check(lanes >= 2, "resource sample did not exercise buff and debuff lanes")
    for _, key in ipairs({ "hpBar", "incomingHealBar", "absorbBar", "healAbsorbBar", "tempMaxHealthBar",
        "nameText", "raidTargetIcon", "MSUFPortraitHolder" }) do
        local region = frame[key]
        Check(not region or not region:IsShown(), "resource strip leaks " .. key)
    end
    local powerRow = powerSurface.root.parent:GetParent()
    MenuWorld.FireVisibilityScripts(powerRow:GetParent())
    local pickers = 0
    M.Widgets.OpenColorContextPicker = function() pickers = pickers + 1 end
    powerRow:Click("LeftButton")
    Settle()
    local power = M.cache.opt_colors.sections.colors_power._msuf2CollapsibleEntry
    Check(power and power.open, "resource click did not open power selection")
    local resourceRow
    for _, child in ipairs({ powerRow:GetParent():GetChildren() }) do
        if child ~= powerRow and child:GetObjectType() == "Button" then resourceRow = child end
    end
    Check(resourceRow ~= nil, "class resource click target is missing")
    resourceRow:Click("LeftButton")
    Settle()
    local cp = M.cache.opt_colors.sections.colors_class_power._msuf2CollapsibleEntry
    Check(cp and cp.open, "resource click did not open class resource selection")
    Check(pickers == 0, "resource selection click opened a color picker")
    local function Control(suffix)
        suffix = suffix:gsub("_", ".")
        for _, widget in ipairs(M.cache.opt_colors.searchWidgets) do
            local record = widget._msuf2RuntimeControlRecord
            if record and record.controlId:sub(-#suffix) == suffix then return widget end
        end
        error("missing color control " .. suffix)
    end
    for _, token in ipairs({ "ENERGY", "MANA", "RAGE" }) do
        Control("power.editor.resource_selector")._msuf2OnValueChanged(token)
        Settle()
        Check(M.colorsPowerToken == token, "power selector rejected " .. token)
        Check(powerSurface.scene.sample.powerToken == token, "power preview retained old resource")
    end
    local choice = flavor == "Mainline" and "HOLY_POWER" or "COMBO_POINTS"
    Control("class_power.editor.resource_selector")._msuf2OnValueChanged(choice)
    Settle()
    Check(M.colorsCPToken == choice, "class resource selector rejected selection")
    Category("auras")
    Check(not powerSurface.root:IsActive(), "hidden resources retained an active scene")
    Category("resources")
    Check(powerSurface.root:IsActive(), "returning to resources did not reactivate its scene")
    Check(powerSurface.scene.sample.powerToken == "RAGE", "cached resources lost selected power")
end
Check(#mw.world.reported == 0, "menu reported errors")
print("menu_colors_preview_regressions_smoke " .. flavor .. " " .. mode .. ": " .. checks .. " checks pass")
