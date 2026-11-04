-- menu_preview_health_loss_smoke.lua <root> <flavor>
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and (failure.file .. ": " .. failure.message))
local env, MSUF, methods = world.env, world.core, world.widgets.Methods
local valueWrites = setmetatable({}, { __mode = "k" })
local smoothWrites = setmetatable({}, { __mode = "k" })
local setValue = methods.SetValue
methods.SetValue = function(self, value, interpolation)
    valueWrites[self] = (valueWrites[self] or 0) + 1
    if interpolation ~= nil and interpolation == self._msufSmoothInterp then
        smoothWrites[self] = (smoothWrites[self] or 0) + 1
    end
    return setValue(self, value, interpolation)
end
-- The widget fixture records native animations but does not advance them.
local now, playing = 0, {}
local play = methods.Play
methods.Play = function(self)
    play(self)
    local duration = 0
    for _, animation in ipairs(self.animations or {}) do duration = duration + (animation.duration or 0) end
    playing[self] = now + duration
end
local function Advance()
    now = now + 0.06
    for animation, finish in pairs(playing) do
        if not animation:IsPlaying() then playing[animation] = nil
        elseif now >= finish then
            animation:Finish()
            local finished = animation:GetScript("OnFinished")
            if finished then finished(animation) end
            playing[animation] = nil
        end
    end
end
for _, key in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetAutoFocus", "SetMaxLetters",
    "EnableKeyboard", "SetNumeric", "SetTextInsets", "ClearFocus", "SetCursorPosition", "HighlightText",
    "SetPropagateKeyboardInput", "SetPropagateMouseWheel", "SetValueStep", "SetObeyStepOnDrag" }) do
    methods[key] = methods[key] or function() end
end
methods.GetFont = methods.GetFont or function() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
(env.MSUF_EnsureDB or MSUF.MSUF_EnsureDB)(true)
local M, Preview = MSUF.MSUF2, MSUF.UFPreview
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
local currentKey = "player"
panel._msufGetCurrentKey = function() return currentKey end
local unit = Preview._BuildPreview(parent, panel, 900, 400)
unit:Show()
unit.canvas:SetSize(400, 200)
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, flavor .. ": " .. message)
end
local function Exercise(box, conf, refresh, getBar, action, label)
    local isUnit = box == unit
    local function SetAnimation(enabled)
        if isUnit then
            local button = box.animateCombatButton
            if action.get() ~= enabled then assert(button:GetScript("OnClick"))(button) end
            return action.get() == enabled
        end
        return action.set(enabled)
    end
    conf.chunkedFill, conf.smoothFill = true, false
    conf.hpBarAlpha, conf.frameBarShape = 0.35, "SQUARE"
    env.MSUF_DB.general.healthLossColorR = 0.8
    env.MSUF_DB.general.healthLossColorG = 0.4
    env.MSUF_DB.general.healthLossColorB = 0.1
    MSUF.UF.Config.Refresh()
    if not isUnit then MSUF.GF.InvalidateCompiledSpecs(label) end
    refresh()
    local staticValue = isUnit and getBar():GetValue()
    Check(SetAnimation(true), label .. ": animation did not start")
    local tick = assert(box:GetScript("OnUpdate"))
    tick(box, 0.06)
    local bar = assert(getBar())
    Check(bar._msufChunkedLoss == true, label .. ": configured chunked loss missing on menu bar")
    local trail = assert(bar._msufLossTrail, label .. ": missing loss trail")
    Check(trail:GetStatusBarTexture():GetAlpha() == bar:GetStatusBarTexture():GetAlpha(),
        label .. ": loss opacity differs from health fill")
    if bar._msufPreviewHealthLoss then
        Check(trail:GetFrameLevel() < bar:GetFrameLevel(), label .. ": loss draws above healing and absorb previews")
    end
    local r, g, b = trail:GetStatusBarColor()
    Check(r == 0.8 and g == 0.4 and b == 0.1, label .. ": configured health loss color missing")
    local last, drops, stable = bar:GetValue(), 0, 0
    local writes = valueWrites[bar] or 0
    for _ = 1, 160 do
        Advance()
        tick(box, 0.06)
        local value = bar:GetValue()
        if value == last then stable = stable + 1 end
        if value < last then
            drops = drops + 1
            Check(trail._msufLossAnimating == true, label .. ": loss did not start native fade")
            Check(trail:GetValue() > value, label .. ": trail did not retain pre-damage health")
        end
        last = value
    end
    Check(drops > 0 and stable > 80, label .. ": chunked sample should hold between discrete losses")
    Check((valueWrites[bar] or 0) - writes < 40, label .. ": unchanged chunks still write health every tick")
    Check(SetAnimation(false), label .. ": animation did not stop")
    refresh()
    if isUnit then Check(getBar():GetValue() == staticValue, label .. ": chunked stop did not restore static health") end
    Check(trail._msufLossAnimating ~= true and not trail:IsShown(), label .. ": Stop left loss trail active")
    box._msuf2RangeFadePreviewAlpha, box._msuf2RangeFadePreviewLayerMode = 0.4, "health"
    refresh()
    Check(math.abs(trail:GetStatusBarTexture():GetAlpha() - bar:GetStatusBarTexture():GetAlpha() * bar:GetAlpha()) < 0.0001,
        label .. ": loss ignores health-only range fade")
    if not bar._msufPreviewHealthLoss and not isUnit then
        local frame = box._msufGFRenderState.mock._cell
        MSUF.UF.elements.Alpha.SceneApply(frame, frame.MSUFSpec)
        refresh()
        Check(math.abs(trail:GetStatusBarTexture():GetAlpha() - bar:GetStatusBarTexture():GetAlpha() * bar:GetAlpha()) < 0.0001,
            label .. ": native alpha repaint invalidated range fade")
    end
    box._msuf2RangeFadePreviewAlpha, box._msuf2RangeFadePreviewLayerMode = nil, nil
    conf.reverseFillBars, conf.reverseFill = true, true
    conf.verticalFillBars = isUnit
    conf.frameBarShape = "ROUNDED"
    MSUF.UF.Config.Refresh()
    if not isUnit then MSUF.GF.InvalidateCompiledSpecs(label) end
    refresh()
    Check((trail:GetOrientation() or "HORIZONTAL") == (bar:GetOrientation() or "HORIZONTAL"),
        label .. ": loss trail uses another fill axis")
    Check(trail:GetReverseFill() == bar:GetReverseFill(), label .. ": loss trail uses another fill direction")
    if bar._msufPreviewHealthLoss then
        Check(#trail:GetStatusBarTexture().masks >= 2, label .. ": shaped loss trail lacks its frame mask")
    end
    conf.frameBarShape = "SQUARE"
    MSUF.UF.Config.Refresh()
    if not isUnit then MSUF.GF.InvalidateCompiledSpecs(label) end
    refresh()
    if bar._msufPreviewHealthLoss then
        Check(#trail:GetStatusBarTexture().masks == 1, label .. ": square loss trail retained a shape mask")
    end
    conf.chunkedFill, conf.smoothFill = false, true
    MSUF.UF.Config.Refresh()
    if not isUnit then MSUF.GF.InvalidateCompiledSpecs(label) end
    refresh()
    Check(getBar()._msufChunkedLoss ~= true, label .. ": disabling chunked did not restore ordinary fill")
    Check(getBar()._msufSmoothInterp ~= nil, label .. ": smooth mode was lost when changing modes")
    if isUnit then
        local smoothStaticValue = getBar():GetValue()
        Check(SetAnimation(true), label .. ": smooth animation did not start")
        local smoothTick = assert(box:GetScript("OnUpdate"))
        smoothTick(box, 0.06)
        local smoothBar = assert(getBar())
        local initialValue = smoothBar:GetValue()
        local writesBefore = smoothWrites[smoothBar] or 0
        local changed = false
        for _ = 1, 40 do
            Advance()
            smoothTick(box, 0.06)
            changed = changed or smoothBar:GetValue() ~= initialValue
        end
        Check(changed and (smoothWrites[smoothBar] or 0) > writesBefore,
            label .. ": animated health changes bypassed native interpolation")
        Check(SetAnimation(false), label .. ": smooth animation did not stop")
        refresh()
        Check(getBar():GetValue() == smoothStaticValue, label .. ": smooth stop did not restore static health")
    end
    box:Hide()
end
for _, key in ipairs({ "player", "targettarget", "focustarget", "pettarget" }) do
    if MSUF.Client.SupportsUnit(key) then
        currentKey = key
        unit:Show()
        Exercise(unit, MSUF.UF.Config.GetUnitDB(key),
            function()
                Preview.Refresh(unit, "HEALTH_LOSS_TEST")
                assert(unit.key == key, "preview did not select " .. key)
            end,
            function() return unit._unitScene and unit._unitScene:Frame().hpBar or unit.mock.healthBar end,
            unit.animateCombatButton._msuf2CommandAction, key)
    end
end
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
MSUF.GF.EnsureDB()
for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    if MSUF.Client.SupportsGroupKind(scope) then
        M.gfScope = scope
        local group = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
        group:Show()
        group._stage:SetSize(600, 220)
        local conf = M.GroupPage.Conf(scope)
        Exercise(group, conf, function() group:Refresh("SETTINGS") end,
            function()
                local mock = group._msufGFRenderState.mock
                return unit._unitScene and mock._cell.hpBar or mock._health
            end, group._previewAnimationButton._msuf2CommandAction, scope)
    end
end
print("menu_preview_health_loss_smoke: " .. flavor .. " " .. checks .. " checks passed")
