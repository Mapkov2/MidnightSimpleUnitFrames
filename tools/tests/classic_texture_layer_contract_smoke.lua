local root = assert(arg[1])
local menu = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
-- Every client loads the one unified page; the retired Classic copy must stay gone.
assert(io.open(menu .. "Pages/MSUF_Menu2_UnitTextureLayer_Classic.lua", "rb") == nil,
    "retired Classic Texture Layer page is back")
do
    local ns = { MSUF2 = {}, ExportPublic = function(name, value) _G[name] = value end }
    assert(loadfile(menu .. "MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", ns)
    local M = ns.MSUF2
    local section
    M.UnitPage = { RegisterSection = function(spec) section = spec end }
    local UP = M.UnitPage
    for _, name in ipairs({ "ReadBool", "SetBool", "ReadNumber", "SetNumber", "SetString",
        "SetControlEnabled", "GetConf", "ReviewedMeta" }) do
        UP[name] = function() return {} end
    end
    assert(UP.Call == nil, "removed wrapper must not exist in fixture")
    assert(loadfile(menu .. "Pages/MSUF_Menu2_UnitTextureLayer.lua"))("MidnightSimpleUnitFrames_Options", ns)
    assert(section and section.id == "texture_layer", "Texture Layer section was not registered")
    -- Stop exactly where real UI construction starts. The regression returned
    -- silently before this boundary solely because the unused UP.Call was absent.
    local reached = {}
    local builder = { CollapsibleSection = function(_, id)
        assert(id == "texture_layer")
        error(reached)
    end }
    local ok, err = pcall(section.build, { width = 720 }, builder, "player")
    assert(not ok and err == reached, "Texture Layer did not reach UI construction: " .. tostring(err))
    UP.GetConf = nil
    ok, err = pcall(section.build, {}, builder, "player")
    assert(not ok and tostring(err):find("Texture Layer requires the UnitPage settings API", 1, true),
        "missing required settings API must fail visibly")
end
-- Drive the real slot bar and dropdown rows after lazy construction. Choosing
-- the new tint must write only the selected texture slot, not the HP settings.
local function SelectNPCMode(flavor)
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local mw = MenuWorld.Open(root, flavor, { page = "home", locale = "deDE",
        beforeOptions = function(world) assert(world.core.FinalizeLocale() == "deDE") end })
    local M, db = mw.M, mw.env.MSUF_DB
    -- Unit-frame construction uses native health APIs outside this menu contract.
    mw.env.MSUF_UFCore_NotifyConfigChanged = function() return true end
    local dropdown, slotBar
    local Dropdown, ScopeBar = M.Widgets.Dropdown, M.Widgets.ScopeOverrideBar
    M.Widgets.Dropdown = function(parent, label, ...)
        local control = Dropdown(parent, label, ...)
        if label == "Color mode" then dropdown = control end
        return control
    end
    M.Widgets.ScopeOverrideBar = function(ctx, section, opts)
        local control = ScopeBar(ctx, section, opts)
        if opts.label == "Texture:" then slotBar = control end
        return control
    end
    local conf = db.target
    conf.texLayerEnabled, conf.texLayer2Enabled, conf.texLayer3Enabled = true, true, true
    conf.texLayerColorMode, conf.texLayer2ColorMode, conf.texLayer3ColorMode = "CLASS", "CUSTOM", "HEALTH"
    db.general.barMode, db.general.npcColorMode = "BLACK", "reaction"
    db.general.npcTypeColorBar, db.general.npcTypeTarget, db.general.npcTypeBoss = false, false, false
    assert(mw:Select("uf_target") ~= false, flavor .. ": target page unavailable")
    local function OpenSection()
        local section = assert(M.cache.uf_target.sections.texture_layer)
        M.Widgets.FocusCollapsibleSection(section, { persist = true, flash = false })
        mw:RunTimers()
        assert(dropdown and slotBar, flavor .. ": texture controls did not build")
    end
    OpenSection()
    for _, slot in ipairs({ 2, 3 }) do
        slotBar.buttons[slot]:Click()
        OpenSection()
        assert(M.unitTexLayerSlot.target == slot, flavor .. ": actual slot click did not select slot")
        dropdown:Click()
        local choice
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame._msuf2Owner == dropdown and frame._msuf2Value == "CLASS_NPC" and frame:IsShown() then
                choice = frame
                break
            end
        end
        assert(choice, flavor .. ": new color option missing from open dropdown")
        assert(choice._msuf2Text:GetText() == "Klassenfarbe / NPC-Typ", flavor .. ": new option is not translated: " .. tostring(choice._msuf2Text:GetText()))
        choice:Click()
        mw:RunTimers()
        assert(conf["texLayer" .. slot .. "ColorMode"] == "CLASS_NPC", flavor .. ": selected slot did not store new mode")
        assert(dropdown:GetValue() == "CLASS_NPC", flavor .. ": dropdown selection did not refresh")
        assert(dropdown._msuf2Label:GetText() == "Klassenfarbe / NPC-Typ", flavor .. ": selected label did not refresh")
        assert(conf.texLayerColorMode == "CLASS", flavor .. ": changed unselected first slot")
        assert(conf.texLayer2ColorMode == "CLASS_NPC", flavor .. ": lost second slot selection")
        assert(db.general.barMode == "BLACK" and db.general.npcColorMode == "reaction"
            and db.general.npcTypeColorBar == false and db.general.npcTypeTarget == false
            and db.general.npcTypeBoss == false, flavor .. ": texture mode changed HP or NPC settings")
    end
end
for _, flavor in ipairs({ "Mainline", "Vanilla", "Forever" }) do SelectNPCMode(flavor) end
print("PASS Texture Layer: required API, real NPC dropdown actions, three-slot isolation and German labels")
