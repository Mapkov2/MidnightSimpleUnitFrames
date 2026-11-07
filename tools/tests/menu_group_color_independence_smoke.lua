-- Group colors, contextual pickers and compiled health specs own their scope.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, selected = arg[2] or "Mainline", arg[3]
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "opt_colors", clientScriptBindings = true,
    beforeCore = function(world) world.env.MAX_TOTEMS = 4 end })
local M, GF = mw.M, mw.core.GF
mw.env.TotemFrame = false
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, "menu_group_color_independence: " .. message)
end
local function Settle()
    for _ = 1, 12 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(500)
    end
end
Settle()
local db = M.EnsureDB()
local general = db.general
local scopes = { "party", "raid", "mythicraid" }
general.barMode, general.enableHealthGradient = "dark", false
general.barBgColorMode, general.barBgFillMode = "class", "full"
general.healthGradientLowR, general.healthGradientLowG, general.healthGradientLowB = .71, .12, .23
for _, kind in ipairs(scopes) do
    db["gf_" .. kind].gfBarMode = "GRADIENT"
end
mw.core.UF.Config.Refresh()
local function Targets(ref, scope)
    return M.ResolveContextColorReferences({ ref }, { group = true, scope = scope, healthMode = "GRADIENT" })
end
local function GlobalUntouched()
    Check(general.barMode == "dark" and general.enableHealthGradient == false, "group edit enabled unit gradient")
    Check(general.healthGradientLowR == .71 and general.healthGradientLowG == .12
        and general.healthGradientLowB == .23, "group edit changed unit stops")
    Check(general.barBgColorMode == "class" and general.barBgFillMode == "full", "group edit changed unit background")
end
if not selected or selected == "runtime" then
    for _, kind in ipairs(scopes) do
        local conf = db["gf_" .. kind]
        GF.InvalidateCompiledSpecs(kind)
        local spec = GF.GetCompiledSpec(kind)
        Check(spec.health.mode == "gradient", kind .. " gradient depends on unit enable")
        Check(spec.health.gradientLowR == .71, kind .. " lost inherited stops")
        for _, stop in ipairs({ "Low", "Mid", "High" }) do
            for i, channel in ipairs({ "R", "G", "B" }) do
                conf["healthGradient" .. stop .. channel] = i / 10
            end
        end
        conf.barBgColorMode, conf.barBgFillMode = "health_gradient", "missing"
        GF.RefreshCompiledSpecDomains(kind, GF.DIRTY_COLOR)
        local refreshed = GF.GetCompiledSpec(kind)
        Check(refreshed == spec, "color refresh discarded cached spec")
        for _, stop in ipairs({ "Low", "Mid", "High" }) do
            for i, channel in ipairs({ "R", "G", "B" }) do
                Check(spec.health["gradient" .. stop .. channel] == i / 10, kind .. " ignores scoped gradient channel")
            end
        end
        local frame = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
        Check(GF.GetCompiledSpec(kind, frame, "raid1").health.gradientLowG == .2, "frame spec lost group colors")
        Check(spec.health.backgroundColorMode == "health_gradient" and spec.health.backgroundFillMode == "missing",
            kind .. " ignores scoped background")
        GF.InvalidateCompiledSpecs(kind)
        spec = GF.GetCompiledSpec(kind)
        Check(spec.health.gradientHighB == .3 and spec.health.backgroundFillMode == "missing", "fresh compile lost colors")
        for _, stop in ipairs({ "Low", "Mid", "High" }) do
            for _, channel in ipairs({ "R", "G", "B" }) do conf["healthGradient" .. stop .. channel] = nil end
        end
        conf.barBgColorMode, conf.barBgFillMode = nil, nil
    end
end
if not selected or selected == "shortcut" then
    for _, kind in ipairs(scopes) do
        local key, conf = "gf_" .. kind, db["gf_" .. kind]
        local targets = Targets("health.current", key)
        Check(#targets == 3, "gradient shortcut needs three stops")
        for i, target in ipairs(targets) do
            local before = target.captureState()
            if i == 1 then Check(target.getRGB() == .71, "shortcut lost inherited RGB") end
            target.setRGB(.31, .42, .53)
            local stop = ({ "Low", "Mid", "High" })[i]
            Check(conf["healthGradient" .. stop .. "R"] == .31, "shortcut edits the wrong owner")
            for _, other in ipairs(scopes) do
                if other ~= kind then Check(db["gf_" .. other]["healthGradient" .. stop .. "R"] == nil, "shortcut edited sibling") end
            end
            GlobalUntouched()
            target.restoreState(before)
            Check(conf["healthGradient" .. stop .. "R"] == nil, "cancel seeded an inherited color")
        end
        conf.barBgColorMode = "health_gradient"
        targets = Targets("health.background.current", key)
        Check(#targets == 3 and targets[1]._msuf2ContextColorId:find(key, 1, true), "background shortcut ignores scoped mode")
        conf.barBgColorMode = "custom"
        targets = Targets("health.background.current", key)
        local target = assert(targets[1])
        local before, oldR = target.captureState(), conf.bgR
        target.setRGB(.19, .29, .39)
        Check(conf.bgR == .19, "background shortcut missed its scope")
        for _, other in ipairs(scopes) do
            if other ~= kind then Check(db["gf_" .. other].bgR ~= .19, "background shortcut edited sibling") end
        end
        target.restoreState(before)
        Check(conf.bgR == oldR, "background cancel lost original value")
        conf.barBgColorMode = nil
    end
end
if not selected or selected == "controls" then
    M.ColorsEnsureCategoryBuilt("colors_group_frames")
    M.ColorsOnPainterCategory("group_frames")
    Settle()
    local function Control(suffix)
        for _, widget in ipairs(M.cache.opt_colors.searchWidgets) do
            local record = widget._msuf2RuntimeControlRecord
            if record and record.controlId:sub(-#suffix) == suffix then return widget end
        end
        error("group control missing: " .. suffix)
    end
    -- Party CLASS must not lock the shared gradient editor when Raid uses it.
    db.gf_party.gfBarMode = "CLASS"
    M.Refresh()
    local low = Control("group.frame.color.health.gradient.low")
    Check(low:IsEnabled(), "group gradient editor depends on selected unit/group mode")
    M.SyncExternalHistoryState()
    low._msuf2OnColorChanged(.11, .22, .33)
    Settle()
    for _, kind in ipairs(scopes) do Check(db["gf_" .. kind].healthGradientLowR == .11, "shared picker missed " .. kind) end
    GlobalUntouched()
    Check(M.Undo(), "group color is not undoable")
    Settle()
    db, general = M.EnsureDB(), M.EnsureDB().general
    Check(db.gf_raid.healthGradientLowR == nil, "undo lost inheritance")
    Check(M.Redo(), "group color is not redoable")
    Settle()
    db, general = M.EnsureDB(), M.EnsureDB().general
    Check(db.gf_raid.healthGradientLowR == .11, "redo lost group color")
    Control("group.frame.background.color.mode")._msuf2CommandAction.set("health_gradient")
    Control("group.frame.background.fill.mode")._msuf2CommandAction.set("missing")
    Settle()
    for _, kind in ipairs(scopes) do
        Check(db["gf_" .. kind].barBgColorMode == "health_gradient" and db["gf_" .. kind].barBgFillMode == "missing",
            "group background controls missed " .. kind)
    end
    GlobalUntouched()
    local defaults = mw.core.ProfileFields.CopySnapshot(db)
    for _, kind in ipairs(scopes) do
        defaults["gf_" .. kind].healthGradientLowR = nil
        defaults["gf_" .. kind].barBgColorMode = nil
        defaults["gf_" .. kind].barBgFillMode = nil
    end
    mw.core.MSUF_CreateFactoryDefaultProfile = function() return defaults end
    Check(M.ResetPageToDefaults("opt_colors"), "Colors reset failed")
    for _, kind in ipairs(scopes) do
        local conf = M.EnsureDB()["gf_" .. kind]
        Check(conf.healthGradientLowR == nil and conf.barBgColorMode == nil and conf.barBgFillMode == nil,
            "Colors reset missed scoped colors")
    end
end
print("menu_group_color_independence: " .. flavor .. " " .. checks .. " checks passed")
