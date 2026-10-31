-- menu_preview_power_loss_smoke.lua <root> <flavor>
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and (failure.file .. ": " .. failure.message))
local env, MSUF, methods = world.env, world.core, world.widgets.Methods
-- Native visibility includes hidden parents; the shared fixture normally models only IsShown.
methods.IsVisible = function(self)
    while self do
        if not self:IsShown() then return false end
        self = self:GetParent()
    end
    return true
end
local valueWrites = setmetatable({}, { __mode = "k" })
local setValue = methods.SetValue
methods.SetValue = function(self, value, interpolation)
    valueWrites[self] = (valueWrites[self] or 0) + 1
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
panel._msufGetCurrentKey = function() return "player" end
local unit = Preview._BuildPreview(parent, panel, 900, 400)
unit:Show()
unit.canvas:SetSize(400, 200)
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, flavor .. ": " .. message)
end
local function Exercise(box, conf, refresh, getBar, action, label, scope)
    conf.chunkedFill, conf.smoothFill = false, false
    conf.powerChunkedFill, conf.powerSmoothFill, conf.powerBarEnabled = true, false, true
    conf.powerBarAlpha, conf.frameBarShape = 0.35, "SQUARE"
    env.MSUF_DB.general.powerLossColorR, env.MSUF_DB.general.powerLossColorG, env.MSUF_DB.general.powerLossColorB = 0.7, 0.9, 1
    local function Apply()
        MSUF.UF.Config.Refresh()
        if scope then MSUF.GF.InvalidateCompiledSpecs(scope) end
        refresh()
    end
    Apply()
    Check(action.set(true) == true, label .. ": Animate did not start")
    local tick = assert(box:GetScript("OnUpdate"))
    tick(box, 0.06)
    local bar = assert(getBar(), label .. ": power preview has no native value carrier")
    Check(bar._msufChunkedLoss == true, label .. ": chunked power loss missing")
    local trail = assert(bar._msufLossTrail)
    local pool = trail._msufLossTrailPool or { trail }
    local function AlphaCheck()
        for _, snapshot in ipairs(pool) do
            local _, _, _, lossA = snapshot:GetStatusBarColor()
            local source = bar._msufPreviewPowerSource
            local actual, expected
            if source then
                actual = (lossA or 1) * snapshot:GetStatusBarTexture():GetAlpha()
                expected = source:GetAlpha() * bar:GetAlpha()
            else
                local _, _, _, a = bar:GetStatusBarColor()
                actual = (lossA or 1) * snapshot:GetStatusBarTexture():GetAlpha()
                expected = (a or 1) * bar:GetStatusBarTexture():GetAlpha() * bar:GetAlpha()
            end
            Check(math.abs(actual - expected) < 0.0001, label .. ": loss opacity differs from power")
        end
    end
    AlphaCheck()
    local last, drops, stable, writes = bar:GetValue(), 0, 0, valueWrites[bar] or 0
    for _ = 1, 160 do
        Advance()
        tick(box, 0.06)
        local value = bar:GetValue()
        if value == last then stable = stable + 1 end
        if value < last then
            drops = drops + 1
            local loss = false
            for _, snapshot in ipairs(pool) do
                if snapshot._msufLossAnimating and snapshot:GetValue() == last then loss = true end
            end
            Check(loss, label .. ": spent power did not retain a native loss snapshot")
        end
        last = value
    end
    Check(drops > 0 and stable > 80, label .. ": power should hold between spend steps")
    Check((valueWrites[bar] or 0) - writes < 40, label .. ": stable power still writes every tick")
    if scope then
        M.gfPreviewSoloLayer = "health"
        Apply()
        tick(box, 0.06)
        AlphaCheck()
        M.gfPreviewSoloLayer = nil
    end
    if not scope then
        box.layerVisibility.power = false
        MSUF.UFPreviewCore.ApplyLayerVisibility(box)
    else
        M.gfPreviewLayerVisible = M.gfPreviewLayerVisible or {}
        M.gfPreviewLayerVisible.power = false
        Apply()
    end
    for _ = 1, 20 do Advance(); tick(box, 0.06) end
    for _, snapshot in ipairs(pool) do Check(not snapshot:IsShown(), label .. ": hidden Power layer leaked loss") end
    if not scope then box.layerVisibility.power = true else M.gfPreviewLayerVisible.power = true end
    action.set(false)
    Apply()
    for _, snapshot in ipairs(pool) do
        Check(not snapshot._msufLossAnimating and not snapshot:IsShown(), label .. ": Stop retained spent power")
    end
    conf.frameBarShape = "ROUNDED"
    conf.verticalFillBars, conf.reverseFillBars = true, true
    Apply()
    local newTrail = getBar()._msufLossTrail
    if bar._msufPreviewPowerLoss and (scope or not conf.detachedPowerBarShape or conf.detachedPowerBarShape == "BAR") then
        Check(#newTrail:GetStatusBarTexture().masks >= 2, label .. ": rounded power loss lacks frame mask")
    end
    if bar._msufPreviewPowerSource then
        local shape = conf.powerBarDetached and M.ClassPowerPreview.POWER_SHAPES[unit._runtimeDetachedPowerShape or "BAR"]
        if shape then
            Check(bar:GetOrientation() == (shape.axis or "HORIZONTAL"), label .. ": shaped carrier uses wrong axis")
            Check(not bar:GetReverseFill(), label .. ": shaped carrier clips from wrong edge")
        end
    end
    conf.frameBarShape = "SQUARE"
    Apply()
    if bar._msufPreviewPowerLoss then
        Check(#newTrail:GetStatusBarTexture().masks == 1, label .. ": square power loss retained shape mask")
    end
    conf.powerChunkedFill, conf.powerSmoothFill = false, true
    Apply()
    Check(not getBar()._msufChunkedLoss, label .. ": chunked toggle did not release native wrapper")
    box:Hide()
end
local function UnitBar()
    return unit._unitScene and unit._unitScene:Frame().targetPowerBar or unit.mock._msufPreviewPowerBar
end
for _, shape in ipairs({ "EMBEDDED", "BAR", "ROUND", "CRYSTAL", "ORB" }) do
    local detached = shape ~= "EMBEDDED"
    env.MSUF_DB.player.powerBarDetached = detached
    env.MSUF_DB.player.detachedPowerBarShape = detached and shape or "BAR"
    unit:Show()
    Exercise(unit, env.MSUF_DB.player, function() Preview.Refresh(unit, "POWER_LOSS_TEST") end,
        UnitBar, unit.animateCombatButton._msuf2CommandAction, "unit " .. shape)
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
        Exercise(group, M.GroupPage.Conf(scope), function() group:Refresh("SETTINGS") end,
            function()
                local mock = group._msufGFRenderState.mock
                return unit._unitScene and mock._cell.targetPowerBar or mock._power
            end, group._previewAnimationButton._msuf2CommandAction, scope, scope)
    end
end
print("menu_preview_power_loss_smoke: " .. flavor .. " " .. checks .. " checks passed")
