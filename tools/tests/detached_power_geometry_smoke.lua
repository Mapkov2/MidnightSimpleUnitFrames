-- Detached Power geometry through the real client graph, menu and previews.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor, selected = arg[2] or "Mainline", arg[3]
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local mw = MenuWorld.Open(root, flavor, { page = "home", clientScriptBindings = true, nativeButtonLifecycle = true, tocMetadata = true, beforeCore = function(world)
    MenuWorld.InstallNativeUnitInputs(world)
    world.widgets.Methods.GetLeft = function(frame) return frame.left or 0 end
    world.widgets.Methods.GetBottom = function(frame) return frame.bottom or 0 end
    world.widgets.Methods.GetRect = function(frame) return frame:GetLeft(), frame:GetBottom(), math.max(1,frame:GetWidth()), math.max(1,frame:GetHeight()) end
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local env, core, M = mw.env, mw.core, mw.M
-- Native frame/text lifecycle is covered by its own smokes; geometry below applies Power directly.
env.MSUF_UFCore_NotifyConfigChanged = function() end
core.UF.Config.Refresh()
local cases = 0
local function Check(ok, message)
    assert(ok, flavor .. ": " .. message)
    cases = cases + 1
end
local function Configure(width, height, vertical, reverse, anchor)
    local player, bars = env.MSUF_DB.player, env.MSUF_DB.bars
    player.showPower, player.showPowerBar, player.powerBarDetached = true, true, true
    player.detachedPowerBarShape = "BAR"
    player.detachedPowerBarWidth, player.detachedPowerBarHeight = width, height
    player.detachedPowerBarSyncClassPower, player.detachedPowerBarAnchorToClassPower = false, anchor == true
    player.verticalFillBars, player.reverseFillBars = vertical, reverse
    bars.detachedPowerBarWidthMode = nil
    core.UF.Config.Refresh()
    return player, bars
end
local function Control(page, key, id, section, prepare)
    local target = { controlId = id, settingKey = key, sectionId = section,
        prepareKind = prepare and "classPowerWorkspace", prepareValue = prepare }
    local selectedPage, found, exact = M.Search._RoutingAPI.OpenSearchTarget(page, "unrelated", "", nil, nil, target)
    Check(selectedPage and found and exact, "exact route missing for " .. key)
    mw:RunTimers()
    for _, widget in ipairs(mw.world.widgets.frames) do
        local command = widget._msuf2CommandAction
        if command and command.controlId == id then return widget end
    end
    error("control missing: " .. id)
end
local function RunControls()
    Configure(275, 6, false, false)
    for _, page in ipairs({ "uf_player", "classpower" }) do
        local prefix = page == "uf_player" and "menu2.uf_player.unit.power." or "menu2.classpower.advanced.detached.power.layout."
        local section = page == "uf_player" and "power_bar" or "classpower_detached_power"
        local prepare = page == "classpower" and "power" or nil
        for _, field in ipairs({ { "Width", 10, 800 }, { "Height", 2, 800 } }) do
            local suffix = page == "uf_player" and ("detachedpowerbar" .. field[1]:lower()) or field[1]:lower()
            local key = "player.detachedPowerBar" .. field[1]
            local widget = Control(page, key, prefix .. suffix, section, prepare)
            local low, high = widget:GetMinMaxValues()
            Check(low == field[2] and high == field[3], page .. " " .. field[1] .. " limits " .. low .. ".." .. high)
            local value = field[1] == "Width" and 10 or 200
            widget.editBox:SetText(tostring(value))
            widget.editBox:GetScript("OnEnterPressed")(widget.editBox)
            -- The native Slider emits this event when SetValue accepts the edit.
            MenuWorld.FireScript(widget, "OnValueChanged", widget:GetValue())
            Check(env.MSUF_DB.player["detachedPowerBar" .. field[1]] == value, page .. " typed " .. field[1] .. " lost")
        end
    end
    Check(env.MSUF_DB.player.detachedPowerBarSyncClassPower == false, "manual width kept Class Resource sync")
end
local function RunRuntime()
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(40, 200)
    frame.MSUFUnitKey, frame.unit = "player", "player"
    core.UF.AttachFrame(frame, { scope = "unit" })
    for _, size in ipairs({ { 275, 6 }, { 20, 80 }, { 10, 200 }, { 10, 800 }, { 800, 2 } }) do
        for _, vertical in ipairs({ false, true }) do
            for _, reverse in ipairs({ false, true }) do
                Configure(size[1], size[2], vertical, reverse)
                local spec = core.UF.Config.GetSpec("player")
                spec.enabled, spec.power.enabled = true, true
                core.UF.Elements.Power.Apply(frame, spec)
                local bar = frame.targetPowerBar
                Check(bar:GetWidth() == size[1] and bar:GetHeight() == size[2], "runtime geometry changed")
                Check(bar._msufPowerOrientation == (vertical and "VERTICAL" or "HORIZONTAL"), "runtime axis changed")
                Check(bar._msufReverseFill == reverse, "runtime reverse fill changed")
            end
        end
    end
end
local function RunUnitPreview()
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = core.UFPreview._BuildPreview(parent, panel, 900, 400)
    box:Show(); box.canvas:SetSize(600, 260)
    for _, size in ipairs({ { 275, 6 }, { 20, 80 }, { 10, 200 }, { 10, 800 }, { 800, 2 } }) do
        for _, vertical in ipairs({ false, true }) do
            for _, reverse in ipairs({ false, true }) do
                Configure(size[1], size[2], vertical, reverse)
                core.UFPreview.Refresh(box, "SETTINGS")
                local bar = box.mock._body.targetPowerBar
                local scale = bar:GetWidth() / size[1]
                Check(math.abs(bar:GetHeight() / size[2] - scale) < .001, "unit preview aspect ratio clipped")
                Check(math.abs(box._runtimeDetachedPowerW - size[1]) < .001, "unit preview width clipped")
                local point = vertical and (reverse and "TOPLEFT" or "BOTTOMLEFT") or (reverse and "TOPRIGHT" or "TOPLEFT")
                Check(bar._msufPowerOrientation == (vertical and "VERTICAL" or "HORIZONTAL"), "unit preview axis changed")
                Check(box._msufPreviewScene.detachedH == size[2], "unit preview fit clipped the detached height")
            end
        end
    end
end
local function ClassPreview()
    M.activeKey = "classpower"
    M.GetClassPowerPreviewSpec = function() return M.ClassPowerPreviewSpecs.rogue_combo end
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(800, 400)
    local previous = M.Widgets.FixedPreviewSection
    M.Widgets.FixedPreviewSection = function()
        return env.CreateFrame("Frame", nil, parent), env.CreateFrame("Frame", nil, parent)
    end
    local pin, expand = M.Widgets.AttachPinnedPreview, M.Widgets.AttachFixedPreviewExpander
    M.Widgets.AttachPinnedPreview, M.Widgets.AttachFixedPreviewExpander = nil, nil
    local ctx = { key = "classpower", width = 800, entry = {}, wrapper = parent }
    Check(M.ClassPowerStackPreview.Create(ctx, { width = 800 }), "Class Resource preview did not build")
    M.Widgets.FixedPreviewSection, M.Widgets.AttachPinnedPreview, M.Widgets.AttachFixedPreviewExpander = previous, pin, expand
    return ctx.entry.classPowerPreview
end
local function RunClassPreview()
    Configure(10, 200, true, false, true)
    local box = ClassPreview()
    for _, size in ipairs({ { 275, 6 }, { 20, 80 }, { 10, 200 }, { 10, 800 }, { 800, 2 } }) do
        for _, vertical in ipairs({ false, true }) do
            for _, reverse in ipairs({ false, true }) do
                Configure(size[1], size[2], vertical, reverse, true)
                box:Refresh()
                local bar = box.detachedPower
                Check(bar:IsShown() and bar:GetWidth() == size[1] and bar:GetHeight() == size[2], "linked preview geometry clipped")
                local point = vertical and (reverse and "TOPLEFT" or "BOTTOMLEFT") or (reverse and "TOPRIGHT" or "TOPLEFT")
                Check(bar._msufPowerOrientation == (vertical and "VERTICAL" or "HORIZONTAL"), "linked preview axis ignored")
                Check(bar._msufReverseFill == reverse, "linked preview reverse ignored")
                box._animationEnabled = true
                box:RefreshAnimation()
                Check(bar._msufPowerOrientation == (vertical and "VERTICAL" or "HORIZONTAL"), "linked animation lost axis")
                Check(bar._msufReverseFill == reverse, "linked animation lost reverse")
                box._animationEnabled = false
            end
        end
    end
    for _, shape in ipairs({ "ROUND", "CRYSTAL", "ORB" }) do
        local player = Configure(40, 60, true, true, true)
        player.detachedPowerBarShape, player.detachedPowerOrbSize = shape, 54
        core.UF.Config.Refresh(); box:Refresh()
        local bar = box.detachedPower
        Check(shape ~= "ORB" or bar:GetWidth() == 54 and bar:GetHeight() == 54, "orb dimensions changed")
        Check(bar._msufPowerOrientation == (shape == "ORB" and "VERTICAL" or "HORIZONTAL"), "shape axis changed")
    end
end
local function RunWidthSources()
    local player, bars = Configure(10, 200, true, false)
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(40, 200); frame.MSUFUnitKey, frame.unit = "player", "player"
    core.UF.AttachFrame(frame, { scope = "unit" })
    core.UF.Elements.Power.Apply(frame, core.UF.Config.GetSpec("player"))
    local previousClass, previousResolver = rawget(env, "MSUF_ClassPowerContainer"), rawget(env, "EssentialCooldownViewer")
    local anchor = env.CreateFrame("Frame", nil, env.UIParent)
    anchor:SetSize(92, 12); anchor._msufAnchorOnly = true; anchor:Show()
    local cooldown = env.CreateFrame("Frame", nil, env.UIParent); cooldown:SetSize(135, 20); cooldown:Show()
    env.MSUF_ClassPowerContainer = anchor
    env.EssentialCooldownViewer = cooldown
    local function Width(expected, label)
        core.UF.Config.Refresh()
        local power = core.UF.Config.GetSpec("player").power
        Check(core.UF.Elements.Power.ResolveDetachedWidth(frame, power) == expected, label .. " runtime width")
        Check(M.ClassPowerPreview.ResolveDetachedPowerWidth({ widthMode = bars.detachedPowerBarWidthMode,
            syncClass = player.detachedPowerBarSyncClassPower ~= false, classWidth = 92,
            explicitWidth = player.detachedPowerBarWidth, manualWidth = player.detachedPowerBarWidth,
            frameWidth = core.UF.Config.GetSpec("player").width }) == expected, label .. " fallback preview width")
    end
    Width(10, "manual")
    player.detachedPowerBarSyncClassPower = true; Width(92, "Class Resource sync")
    bars.detachedPowerBarWidthMode = "cooldown"; Width(135, "Cooldown source wins")
    cooldown:Hide(); Width(92, "hidden Cooldown falls back to Class Resource")
    bars.detachedPowerBarWidthMode, player.detachedPowerBarSyncClassPower = nil, false
    Width(10, "manual restored")
    player.detachedPowerBarWidth = nil
    core.UF.Config.Refresh()
    Check(player.detachedPowerBarWidth == nil, "compiling an old profile materialized an optional width")
    env.MSUF_ClassPowerContainer, env.EssentialCooldownViewer = previousClass, previousResolver
end
local function RunPopups()
    Configure(10, 200, true, false)
    local UF, EM = core.UF, env.MSUF_EM2
    local previousApply, previousOwner = UF.Apply, UF.frames.player
    local owner = env.CreateFrame("Button", nil, env.UIParent)
    owner:SetSize(40, 200); owner.MSUFUnitKey, owner.unit = "player", "player"
    UF.AttachFrame(owner, { scope = "unit" }); UF.frames.player = owner
    UF.Apply = function() return true end
    Check(EM.State.Enter("player"), "popup Edit Mode entry")
    mw:RunTimers()
    for _, key in ipairs({ "player", "power_player" }) do
        Configure(10, 200, true, false)
        UF.Elements.Power.Apply(owner, UF.Config.GetSpec("player")); owner.targetPowerBar:Show()
        Check(EM.Popups.Open(key), key .. " popup did not open")
        local popup
        local name = key == "player" and "MSUF_EM2_UnitPopup" or "MSUF_EM2_ResourcePopup"
        for _, frame in ipairs(mw.world.widgets.frames) do if frame.frameName == name then popup = frame end end
        Check(popup ~= nil, key .. " popup fixture missing")
        local width = key == "player" and popup.dpbWBox or popup.wBox
        local height = key == "player" and popup.dpbHBox or popup.hBox
        Check(tonumber(width:GetText()) == 10 and tonumber(height:GetText()) == 200, key .. " popup sync clipped dimensions")
        for _, size in ipairs({ { 10, 800 }, { 800, 2 }, { 0, 1000, 10, 800 }, { 275, 6 } }) do
            width:SetText(tostring(size[1])); height:SetText(tostring(size[2]))
            height:GetScript("OnEnterPressed")(height)
            local player = env.MSUF_DB.player
            Check(player.detachedPowerBarWidth == (size[3] or size[1])
                and player.detachedPowerBarHeight == (size[4] or size[2]), key .. " popup typed dimensions clipped")
            UF.Config.Refresh(); UF.Elements.Power.Apply(owner, UF.Config.GetSpec("player"))
        end
        popup:Hide()
    end
    EM.State.Exit("test")
    UF.Apply, UF.frames.player = previousApply, previousOwner
end
local tests = { controls = RunControls, runtime = RunRuntime, unit = RunUnitPreview,
    linked = RunClassPreview, sources = RunWidthSources, popups = RunPopups }
for _, name in ipairs({ "controls", "runtime", "unit", "linked", "sources", "popups" }) do
    if not selected or selected == name then tests[name]() end
end
print("detached_power_geometry_smoke: " .. flavor .. " PASS (" .. cases .. " assertions)")
