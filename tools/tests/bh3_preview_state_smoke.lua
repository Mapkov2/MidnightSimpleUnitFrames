-- Real core/Options behavior for the reviewed preview and resource findings.
-- Optional BH3_FILE + BH3_BASELINE replace one source module in memory, leaving
-- the shared checkout untouched for an independent red-without-fix run.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local selected = os.getenv("BH3_CASE") or arg[3]
local file, baseline = os.getenv("BH3_FILE"), os.getenv("BH3_BASELINE")
if file and baseline then
    local original = loadfile
    loadfile = function(path)
        if path:gsub("\\", "/") == root .. "/" .. file then path = baseline .. "/" .. file end
        return original(path)
    end
end
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local cases = {}
local function Near(a, b) return math.abs(a - b) < .001 end
local function RGB(value, r, g, b)
    return value and Near(value[1], r) and Near(value[2], g) and Near(value[3], b)
end
local function Open(page, locale)
    return MenuWorld.Open(root, flavor, { page = page or "home", locale = locale, beforeCore = function(world)
        world.widgets.Methods.GetCenter = function(frame)
            return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
        end
    end })
end
local function Unit(mw, key)
    local e, p = mw.env, mw.core.UFPreview
    local parent = e.CreateFrame("Frame", nil, e.UIParent); parent:SetSize(900, 400)
    local panel = e.CreateFrame("Frame", nil, e.UIParent)
    panel._msufGetCurrentKey = function() return key or "player" end
    local box = p._BuildPreview(parent, panel, 900, 400)
    box:Show(); box.canvas:SetSize(600, 260)
    local function Refresh()
        mw.core.UF.Config.Refresh()
        p.Refresh(box, "SETTINGS")
    end
    Refresh()
    return box, Refresh
end
local function Group(mw)
    mw.M.gfScope = "party"
    local box = mw.M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = "gf_layout" })
    box:Show()
    local function Refresh()
        mw.core.UF.Config.Refresh()
        box:Refresh("SETTINGS")
    end
    Refresh()
    return box, Refresh
end
cases["CX5-01"] = function()
    local mw = Open("classpower")
    local M, db, F = mw.M, mw.env.MSUF_DB, mw.core.ProfileFields
    local defaults = F.CopySnapshot(db)
    mw.core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(defaults) end
    local ui = M.ClassPowerWorkspace.current
    ui:Select("extras")
    local keys = {"manaUpcomingCost", "manaCostColor", "resourceMarks"}
    if mw.core.Client.IsRetail and not mw.core.Client.IsForever then
        keys[#keys+1] = "arcaneWindowText"; keys[#keys+1] = "resourceExtraOffsetX"; keys[#keys+1] = "arcaneWindowColor"
    end
    for _, key in ipairs(keys) do db.bars[key] = "edited" end
    local prompt
    M.ShowPrompt = function(_, spec) prompt = spec end
    ui:Reset(); assert(prompt); prompt.onAccept()
    for _, key in ipairs(keys) do assert(F.Equal(db.bars[key], defaults.bars[key]), "cold reset omitted " .. key) end
end
cases["C27-A2"] = function()
    local mw = Open()
    local all, built = mw.M.ResourceExtrasPage.ClientOnlySettings()
    for _, key in ipairs({"resourceExtraWidth", "resourceExtraHeight", "resourceExtraOffsetX", "resourceExtraOffsetY"}) do
        assert(all["bars." .. key], "layout is absent from capability manifest")
        assert((built["bars." .. key] == true) == (mw.core.Client.IsRetail and not mw.core.Client.IsForever), "layout capability differs")
    end
end
cases["C28-A1"] = function()
    local mw = Open(); local db = mw.env.MSUF_DB
    local defaults = mw.core.ProfileFields.CopySnapshot(db)
    mw.core.MSUF_CreateFactoryDefaultProfile = function() return defaults end
    local keys = {"unifiedBarR", "darkBarG", "darkBarGray", "barBgFillMode", "tapDeniedGray", "aurasCooldownTextWarningSeconds"}
    for _, key in ipairs(keys) do db.general[key] = "edited" end
    db.general.fontSlug = "keep-font"
    assert(mw.M.ResetPageToDefaults("opt_colors"))
    for _, key in ipairs(keys) do assert(db.general[key] == defaults.general[key], "reset skipped " .. key) end
    assert(db.general.fontSlug == "keep-font", "Colors took font ownership")
end
cases["C28-A5"] = function()
    local mw = Open(); local db = mw.env.MSUF_DB
    local defaults = mw.core.ProfileFields.CopySnapshot(db)
    mw.core.MSUF_CreateFactoryDefaultProfile = function() return defaults end
    db.bars.manaCostColor = {.2,.3,.4}; db.bars.playerHPBarWidth = 333
    db.gf_party.healerManaTextR = .123
    assert(mw.M.ResetPageToDefaults("opt_colors"))
    assert(mw.core.ProfileFields.Equal(db.bars.manaCostColor, defaults.bars.manaCostColor), "extras color survived reset")
    assert(db.gf_party.healerManaTextR == defaults.gf_party.healerManaTextR, "healer mana color survived reset")
    assert(db.bars.playerHPBarWidth == 333, "Colors reset geometry")
end
cases["C28-A2"] = function()
    local mw = Open("classpower"); local M, bars = mw.M, mw.env.MSUF_DB.bars
    M.ColorsPage.SetClassPowerSlotMode("COMBO_POINTS", "custom")
    local ui = M.ClassPowerWorkspace.current
    ui:Select("class")
    for _, entry in ipairs(ui.entries.class) do entry.SetOpenImmediate(true) end
    local found
    for _, widget in ipairs(mw.world.widgets.frames) do
        if widget._msuf2StableSearchLabel == "Combo point colors" then found = widget end
    end
    assert(found and found._msuf2CommandAction, "combo selector missing")
    found._msuf2CommandAction.set("ramp")
    assert(bars.classPowerComboPointColorMode == "ramp", "legacy mirror lost")
    assert(M.ColorsPage.GetClassPowerSlotMode("COMBO_POINTS") == "ramp", "canonical slot mode overrides changed selector")
end
cases["C28-A3"] = function()
    local mw = Open(); local db = mw.env.MSUF_DB
    db.gf_party.gfBarMode, db.gf_raid.gfBarMode = "dark", "unified"
    db.gf_party.gfDarkR, db.gf_raid.gfUnifiedR = .12, .76
    local targets = mw.M.ResolveContextColorReferences({"group.health"}, { scope = "gf_raid", group = true })
    local target = assert(targets[1]); assert(Near(target.getRGB(), .76), "Raid shortcut reads Party")
    local state = target.captureState(); target.setRGB(.3,.4,.5)
    assert(db.gf_raid.gfUnifiedR == .3 and db.gf_party.gfDarkR == .12, "context color writes another scope")
    target.restoreState(state)
    assert(db.gf_raid.gfUnifiedR == .76 and db.gf_party.gfDarkR == .12, "context undo restores another scope")
end
cases["CX5-06"] = function()
    local mw = Open("home", "deDE")
    mw.M.ApplyLocaleSelection("deDE"); mw.core.FinalizeLocale()
    local box = Unit(mw, "target")
    assert(box.mock.nameText:GetText() == mw.M.Tr("Astral Warden"), "untranslated fallback name")
    assert(mw.M.Tr("Astral Warden") ~= "Astral Warden", "locale fixture is not translated")
end
cases["CX5-04"] = function()
    local mw = Open(); local p = mw.core.UFPreview
    local box, refresh = Unit(mw)
    local provider = mw.core.UFPreviewRuntime.DetachedCastbarOffsetForPreviewKey
    assert(p.RefreshDeps._RenderState.DetachedCastbarOffsetForPreviewKey == provider, "projection provider omitted")
    local g = mw.env.MSUF_DB.general
    g.castbarPlayerDetached = true
    p.RefreshDeps._RenderState.DetachedCastbarOffsetForPreviewKey = function() return 100, -70 end
    refresh()
    assert(box._detachedCastProjectedX == 100 and box._detachedCastProjectedY == -70, "detached position not projected")
end
cases["C31-A3"] = function()
    local mw = Open(); local db = mw.env.MSUF_DB
    db.player.showPower, db.player.powerBarDetached = true, false
    db.player.verticalFillBars, db.player.reverseFillBars = true, true
    local box, refresh = Unit(mw)
    local point = box.mock.power:GetPoint()
    assert(point == "TOPLEFT", "vertical reverse power is anchored left")
    local h = box.mock.power:GetHeight()
    assert(h and h < box.mock.powerBG:GetHeight(), "vertical fraction does not change height")
    db.player.verticalFillBars, db.player.reverseFillBars = false, true
    refresh()
    assert(box.mock.power:GetPoint() == "TOPRIGHT", "horizontal reverse power anchored left")
    db.player.powerBarDetached, db.player.detachedPowerBarAnchorToClassPower = true, false
    db.player.verticalFillBars, db.player.detachedPowerBarShape = true, "BAR"
    refresh()
    assert(box.mock.detachedPower.fill:GetPoint() == "TOPLEFT", "detached BAR ignores vertical reverse")
end
local function ShapedPower()
    local mw = Open(); local p = mw.env.MSUF_DB.player
    p.showPower, p.powerBarDetached, p.detachedPowerBarShape = true, true, "CRYSTAL"
    p.powerBarBorderEnabled, p.powerBarBorderThickness = true, 2
    p.powerBarBorderColorR, p.powerBarBorderColorG, p.powerBarBorderColorB = .24,.46,.68
    mw.env.MSUF_DB.bars.detachedPowerBarOutline = 2
    local box, refresh = Unit(mw)
    return mw, box, refresh
end
cases["C31-A1"] = function()
    local mw, box = ShapedPower()
    assert(box.mock.detachedPower.edge:IsShown(), "shape edge missing")
    assert(RGB(box.mock.detachedPower.edge.vertexColor,.24,.46,.68), "shape discards border RGB")
end
cases["C31-A2"] = function()
    local mw, box, refresh = ShapedPower()
    local p = mw.env.MSUF_DB.player
    p.powerBarBgColorMode, p.powerBarBgR, p.powerBarBgG, p.powerBarBgB, p.powerBarBgAlpha = "CUSTOM",.12,.34,.56,.71
    refresh()
    local shaped = box.mock.detachedPower.bg.vertexColor
    p.detachedPowerBarShape = "BAR"; refresh()
    local bar = box.mock.detachedPower.bg.vertexColor
    assert(RGB(shaped,bar[1],bar[2],bar[3]) and Near(shaped[4],bar[4]), "shape ignores configured background")
end
cases["C32-A1"] = function()
    local mw = Open(); local defaults = mw.core.ProfileFields.CopySnapshot(mw.env.MSUF_DB)
    defaults.player.nameOffsetX, defaults.player.nameOffsetY = 7, -4
    local castX, castY = mw.core.UFPreviewCastbar.OffsetFields("player")
    defaults.general[castX], defaults.general[castY] = 24, -183
    mw.core.MSUF_CreateFactoryDefaultProfile = function() return defaults end
    local box = Unit(mw); local p = mw.core.UFPreview
    mw.env.MSUF_UFCore_NotifyConfigChanged = function() end
    mw.env.MSUF_DB.player.nameOffsetX = 90
    p.ResetSelectionOffsets(box, box.handleName, "TEST")
    assert(mw.env.MSUF_DB.player.nameOffsetX == 7, "preview Reset ignores client defaults")
    local x,y = p.DefaultSelectionOffsets(box, box.handleCastbar)
    assert(x == 24 and y == -183, "whole castbar reset ignores factory offsets")
    defaults.auras3 = { shared = { buffGroupOffsetX = 999 }, perUnit = {}, customContainers = { perUnit = {} } }
    for _, unit in ipairs({ "target", "boss", "arena" }) do
        local runtimeUnit = unit == "boss" and "boss1" or unit == "arena" and "arena1" or unit
        defaults.auras3.perUnit[runtimeUnit] = { layout = { buffGroupOffsetX = -3, buffGroupOffsetY = 7,
            debuffGroupOffsetX = 31, debuffGroupOffsetY = -2 } }
        defaults.auras3.customContainers.perUnit[unit] = { items = { { placed = { x = 8, y = -11 } } } }
        local auraBox = Unit(mw, unit)
        x,y = p.DefaultSelectionOffsets(auraBox, auraBox.handleAuraBuffs)
        assert(x == -3 and y == 7, unit .. " aura reset ignored scope-owned factory layout")
        x,y = p.DefaultSelectionOffsets(auraBox, auraBox.handleAuraDebuffs)
        assert(x == 31 and y == -2, unit .. " debuff reset ignored factory layout")
        x,y = p.DefaultSelectionOffsets(auraBox, auraBox.handleAuraCustom1)
        assert(x == 8 and y == -11, unit .. " custom aura reset ignored factory placement")
    end
    defaults.auras3.perUnit.target.layout = nil
    local auraBox = Unit(mw, "target")
    x,y = p.DefaultSelectionOffsets(auraBox, auraBox.handleAuraBuffs)
    assert(x == 0 and y == 36, "missing scope layout inherited unrelated shared settings")
end
cases["C32-A1-nil-factory"] = function()
    local mw = Open(); local calls = 0
    mw.core.MSUF_CreateFactoryDefaultProfile = function() calls = calls + 1; return nil end
    local box = Unit(mw); local p = mw.core.UFPreview
    for _ = 1, 10 do
        local x,y = p.DefaultSelectionOffsets(box, box.handleName)
        assert(x == 4 and y == -4, "missing factory did not use handle defaults")
    end
    assert(calls == 1, "missing factory was retried on every selection")
end
cases["C32-A2"] = function()
    local mw = Open("classpower"); local ui = mw.M.ClassPowerWorkspace.current
    local bars = mw.env.MSUF_DB.bars
    bars.classPowerWidthMode, bars.classPowerWidth = "custom", 0
    bars.playerHPBarEnabled, bars.playerHPBarWidthMode, bars.playerHPBarWidth = true, "custom", 0
    ui:Select("class"); local box = ui.page.ctx.entry.classPowerPreview; box:Refresh()
    assert(Near(box.classPower:GetWidth(), box.playerW - 4), "zero class width differs from player width sentinel")
    assert(Near(box.playerHP:GetWidth(), box.playerW), "zero HP width differs from player width sentinel")
end
cases["C32-A3"] = function()
    local mw = Open("classpower"); local p = mw.env.MSUF_DB.player
    p.showPower, p.powerBarDetached, p.detachedPowerBarShape = true, true, "BAR"
    p.detachedPowerBarAnchorToClassPower = true
    p.powerBarBorderColorR,p.powerBarBorderColorG,p.powerBarBorderColorB = .24,.46,.68
    mw.env.MSUF_DB.bars.detachedPowerBarOutline = 2
    mw.env.MSUF_DB.bars.roundedFramesEnabled = true
    mw.env.MSUF_DB.bars.roundedUnitFrames = true
    mw.env.MSUF_DB.bars.roundedPowerBars = true
    mw.core.UF.Config.Refresh()
    mw.M.ClassPowerWorkspace.current:Select("power")
    local box = mw.M.ClassPowerWorkspace.current.page.ctx.entry.classPowerPreview; box:Refresh()
    local edge = box.detachedPower._msufCPRoundedEdge
    assert(edge and RGB(edge.vertexColor,.24,.46,.68), "class-power preview reads the wrong player border table")
end
cases["C33-A1"] = function()
    local mw = Open(); local conf = mw.env.MSUF_DB.gf_party
    conf.hlOverride, conf.healPrediction, conf.enableAbsorbBar = true, true, true
    conf.healPredAnchorMode, conf.absorbAnchorMode = 1, 1
    local box, refresh = Group(mw); local mock = box._msufGFSceneState.mock
    assert(mock._healPred.reverseFill == false and mock._absorb.reverseFill == false, "LEFT predictions reverse fill")
    conf.reverseFillBars, conf.healPredAnchorMode, conf.absorbAnchorMode = true, 5, 5; refresh()
    assert(mock._healPred.reverseFill == false and mock._absorb.reverseFill == false, "REVERSE_FROM_MAX ignores reversed HP")
end
cases["C33-A2"] = function()
    local mw = Open(); local conf = mw.env.MSUF_DB.gf_party
    conf.showPower, conf.powerBarDetached, conf.showPowerText = true, true, true
    local box = Group(mw); local mock = box._msufGFSceneState.mock
    assert(select(2,mock._hpLeftFS:GetPoint()) == mock._health, "health text anchors to whole frame")
    assert(select(2,mock._powerLeftFS:GetPoint()) == mock._power and mock._powerLeftFS:GetPoint() == "LEFT", "power text ignores its bar")
end
cases["C33-A3"] = function()
    local mw = Open(); local conf = mw.env.MSUF_DB.gf_party
    conf.hlOverride, conf.healAbsorbEnabled, conf.healAbsorbAnchorMode = true, true, 1
    local box = Group(mw); local mock = box._msufGFSceneState.mock
    assert(mock._healAbsorb.reverseFill == false, "LEFT heal absorb follows health")
    assert(mock._healAbsorb.allPoints == mock._health, "fixed heal absorb not anchored to health bar")
end
cases["C33-A4"] = function()
    local mw = Open(); local conf = mw.env.MSUF_DB.gf_party
    conf.healthTextDecimals, conf.hpTextLeft = true, "PERCENT"
    local box = Group(mw)
    local state = box._msufGFHealthTextState
    assert(state and state.percentDecimals == 1, "preview drops configured decimals")
    assert(mw.core.GF.FormatHealthText("PERCENT", 7234, 10000, " / ",false,nil,false,true,0,false,1) == "72.3%", "decimal formatter differs")
end
cases["C33-A5"] = function()
    local mw = Open(); local conf = mw.env.MSUF_DB.gf_party
    conf.portraitMode, conf.portraitOverlayAlign, conf.portraitPlacement = "LEFT", "FULL", "OVERLAY"
    local box = Group(mw); local scene = box._msufGFSceneState
    local holder = scene.mock._msufGroupPortrait
    assert(holder, "portrait fixture missing")
    local owner = holder
    assert(select(2,owner:GetPoint()) == scene.mock._health, "FULL portrait includes power region")
end
cases["C33-A6"] = function()
    local mw = Open(); local box = Group(mw)
    local cfg = box._msuf2SelectionDeps
    assert(cfg, "selection fixture missing")
    local handle
    for _, h in ipairs(box._handleList) do if h._cfgText and h._cfgTextKind == "name" then handle = h end end
    assert(handle)
    local x,y = cfg.DefaultOffsets(box,handle)
    assert(x == mw.core.GF.GetDefault("party","nameOffsetX") and y == mw.core.GF.GetDefault("party","nameOffsetY"), "group defaults are hardcoded")
end
cases["C28-A11"] = function()
    local mw = Open(); mw.env.MSUF_DB.gameplay.crosshairInRangeColor = {.17,.39,.61}
    mw.env.MSUF_DB.gameplay.enableCombatCrosshairMeleeRangeColor = false
    mw:Select("gameplay")
    local count = 0
    for _, frame in ipairs(mw.world.widgets.frames) do
        for _, region in ipairs(frame.regions or {}) do
            if RGB(region.color,.17,.39,.61) or RGB(region.vertexColor,.17,.39,.61) then count = count + 1 end
        end
    end
    assert(count >= 4, "crosshair sample ignores in-range RGB")
end
local count = 0
for id, run in pairs(cases) do
    if not selected or selected == id then
        local ok, message = xpcall(run, debug.traceback)
        assert(ok, id .. " " .. flavor .. ": " .. tostring(message))
        count = count + 1
        print(id .. " " .. flavor .. ": PASS")
    end
end
assert(count > 0, "no selected test case")
