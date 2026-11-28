-- preview_scene_input_contract_smoke.lua <root> <flavor> [source-overlay] [budget]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local activeNative, nativeCalls = false, 0
local liveUnits, portraitRevision = {}, 1
local mw = MW.Open(root, flavor, { page = "home", beforeCore = function(world)
    if arg[4] == "budget" then
        for name, native in pairs(world.widgets.Methods) do
            if type(native) == "function" then
                world.widgets.Methods[name] = function(...)
                    if activeNative then nativeCalls = nativeCalls + 1 end
                    return native(...)
                end
            end
        end
    else
        local methods = world.widgets.Methods
        local setTexture = methods.SetTexture
        function methods:SetTexture(art)
            self.nativePortraitUnit = nil
            setTexture(self, art)
        end
        local registerEvent, registerUnitEvent = methods.RegisterEvent, methods.RegisterUnitEvent
        function methods:RegisterEvent(event)
            self["portraitEventUnit_" .. event] = nil
            registerEvent(self, event)
        end
        function methods:RegisterUnitEvent(event, unit, ...)
            if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
                self["portraitEventUnit_" .. event] = unit
            end
            registerUnitEvent(self, event, unit, ...)
        end
        -- PlayerModel: the stubs have no model widget; record the bound unit.
        local createFrame = world.env.CreateFrame
        world.env.CreateFrame = function(kind, ...)
            local frame = createFrame(kind, ...)
            if kind == "PlayerModel" then
                function frame:SetUnit(unit) self.modelUnit = unit end
                for _, name in ipairs({ "SetKeepModelOnHide", "SetPortraitZoom", "SetCamDistanceScale",
                    "SetViewTranslation", "SetFacing" }) do
                    frame[name] = function() end
                end
            end
            return frame
        end
        world.env.UnitExists = function(unit) return liveUnits[unit] == true end
        world.env.UnitIsPlayer = function(unit) return unit == "player" end
        world.env.SetPortraitTexture = function(texture, unit, unmasked)
            -- GetTexture exposes a render-target name, but SetTexture cannot bind it.
            setTexture(texture, "RTPortrait1")
            texture:SetTexCoord(0, 1, 0, 1)
            texture.nativePortraitUnit, texture.nativePortraitRevision = unit, portraitRevision
            texture.nativePortraitUnmasked = unmasked
            texture.nativePortraitDraws = (texture.nativePortraitDraws or 0) + 1
        end
    end
    if not arg[3] or arg[3] == "-" then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local target = arg[3] .. path:sub(#root + 1)
        local f = io.open(target, "rb")
        if f then f:close() path = target end
        return load(self, path, addon, ns)
    end
end })
local M, GF, env = mw.M, mw.core.GF, mw.env
if arg[4] == "budget" then
    GF.GetConf("party").enabled = true
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box:Show()
    box._stage:SetSize(600, 220)
    box._animationEnabled, box._animationElapsed = true, .5
    box:Refresh("SETTINGS")
    for _ = 1, 4 do assert(box:RefreshAnimation()) end
    local instructions, calls = 0, 0
    debug.sethook(function(event)
        if event == "count" then instructions = instructions + 1
        elseif event == "call" and debug.getinfo(2, "S").what ~= "C" then calls = calls + 1 end
    end, "c", 1)
    for _ = 1, 3 do assert(box:RefreshAnimation()) end
    debug.sethook()
    activeNative = true
    for _ = 1, 3 do assert(box:RefreshAnimation()) end
    activeNative = false
    -- 2026-10-25: identical warm composition before the scene-input transfer.
    assert(instructions <= 42859 * 3 and calls <= 3255 * 3, "preview instruction/call budget regressed")
    assert(nativeCalls <= 821 * 3, "preview widget-native call budget regressed")
    print(string.format("preview_scene_input_contract budget %s: %.0f VM/tick, %.0f Lua calls/tick, %.0f widget-native calls/tick",
        flavor, instructions / 3, calls / 3, nativeCalls / 3))
    return
end
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(500, 300)
local rootScene = GF.NewPreviewScene(host)
local font = { path = "Fonts\\ARIALN.TTF", flags = "MONOCHROME", shadowAlpha = .4, shadowX = 2, shadowY = -2 }
local lane = { enabled = true, max = 1, size = 20, anchor = "TOPLEFT", initialAnchor = "TOPLEFT",
    showCooldownText = true, showStacks = true, showCooldownSwipe = true }
local config = { lanes = { buff = lane }, spellIndicators = { enabled = true, slots = {} } }
mw.core.MSUF_Auras3.ResolveAuraPreviewConfig = function() return config end
GF.GetConf("party").enabled = true
rootScene:Activate()
local group = rootScene:Group("party")
group:Configure({ sample = { font = font, auraTextAlpha = { buff = .25 } } })
group:Show(1, { immediate = true })
local frame = assert(group:Frames()[1])
local visual = assert(frame._msufGFFrameAuraPreviews[1])
local timer = assert(visual._timer)
assert(select(1, timer:GetFont()) == font.path, "scene ignored the requested aura font")
assert(select(3, timer:GetFont()) == font.flags, "scene ignored font flags")
assert(timer:GetAlpha() == .25 and visual._stack:GetAlpha() == .25, "scene ignored the text layer alpha")
font.flags, font.shadowX = "OUTLINE", 3
assert(group:RefreshData())
assert(select(3, timer:GetFont()) == "OUTLINE", "retained scene font cache ignored new flags")
if mw.core.Client.Family == "Mainline" then
    local native, rejected = timer.SetFont, 0
    timer.SetFont = function(self, path, size, flags)
        if path == font.path then rejected = rejected + 1 return false end
        native(self, path, size, flags)
        return true
    end
    font.flags = "MONOCHROME"
    group:RefreshData()
    assert(rejected > 0 and select(1, timer:GetFont()) == env.STANDARD_TEXT_FONT, "native font rejection lost its fallback")
    timer.SetFont = native
end
local owner = env.CreateFrame("Frame", nil, frame)
local number = GF.PreviewSpellSample(frame, owner, { enabled = true, visual = "number", size = 20,
    stackText = "9", font = font, alpha = .4 })
assert(number._stack:GetText() == "9" and select(1, number._stack:GetFont()) == font.path,
    "insertion sample ignored the scene stack/font input")
assert(number:GetAlpha() == .4, "insertion alpha was not painted by the scene")
local Stage
for i = 1, 60 do
    local name, value = debug.getupvalue(M.GroupPreviewRender.Install, i)
    if not name then break end
    if name == "Stage" then Stage = value end
end
local mock = env.CreateFrame("Frame", nil, host)
mock._cell = frame
local handle = env.CreateFrame("Frame", nil, mock)
local placed = { type = "icon", size = 24, cooldownSize = 17, showCooldown = true }
local st = { kind = "party", mock = mock, previewScale = 1, previewFont = font, conf = {},
    scene = { spellIconScale = 1, selectedSpellCfg = {}, selectedPlaced = placed },
    env = { CurrentSpellTexture = function() return 134400 end, CurrentSpellColor = function() return .2, .4, .6 end },
    SetPreviewFont = function() error("Options tried to repaint the scene font") end }
Stage.ConfigureSelectedSpellHandle(st, handle)
local selected = assert(handle._msufEngineVisual)
assert(select(2, selected._timer:GetFont()) == 17, "placed timer size was dropped")
placed.type, placed.size = "number", 4
Stage.ConfigureSelectedSpellHandle(st, handle)
assert(select(2, selected._stack:GetFont()) == 8 and selected._stack:GetText() == "9", "small number sample lost its minimum size")
local surface = M.PreviewHelpers.NewRuntimeUnitSurface(host, "player", {})
surface.layerVisible = { health = false, border = false, nameText = false, hpText = false,
    portrait = false, status = false, auras = false }
local unit = assert(surface:Refresh())
assert(not unit.hpBar:IsShown() and not unit.healthBackgroundBar:IsShown(), "health escaped its scene layer")
surface.scene:RefreshData()
assert(not unit.hpBar:IsShown(), "scene repaint lost its health layer input")
surface.layerVisible.health = true
surface:Refresh()
assert(unit.hpBar:IsShown(), "health layer did not restore")
-- Exercise the real Options adapter too: it must submit the resolved font as
-- scene data before the native group box renders, then let the scene repaint it.
local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
box:Show()
box._stage:SetSize(600, 220)
box:Refresh("SETTINGS")
local native = assert(box._msufGFRenderState.mock._cell)
local cell = assert(box._scene.groups.party)
assert(cell.sample.font == box._msufGFRefreshState.previewFont, "Options did not submit its font before rendering")
local sampleTimer = assert(native._msufGFFrameAuraPreviews[1]._timer)
local path, _, flags = sampleTimer:GetFont()
assert(path == cell.sample.font.path and flags == cell.sample.font.flags, "Options scene font input did not reach its timer")
M.PreviewHelpers.RestoreGroupSceneHandles(box, true)
cell:RefreshData()
assert(select(1, sampleTimer:GetFont()) == path, "scene repaint discarded Options font input")
box:Hide()
rootScene:Deactivate()
-- Open the actual Player preview with an available live portrait.
local Preview = mw.core.UFPreview
local player = env.MSUF_DB.player
player.portraitMode, player.portraitRender, player.portraitShape = "LEFT", "2D", "BLIZZARD"
player.portraitFlip = true
liveUnits.player = true
mw.core.UF.Config.Refresh()
assert(mw:Select("uf_player"))
local playerBox = assert(Preview.active)
local playerFrame = playerBox._unitScene:Frame()
local portrait = assert(playerFrame.portrait)
local function CheckLivePortrait()
    assert(playerBox:IsShown(), "player preview is hidden")
    assert(portrait.nativePortraitUnit == "player", "native portrait never reached the visible preview texture")
    assert(portrait.nativePortraitRevision == portraitRevision, "preview kept an old appearance")
    assert(portrait:IsShown() and playerFrame.MSUFPortraitHolder:IsShown(), "player portrait is hidden")
    assert(playerFrame.MSUFUnitKey == nil and playerFrame:GetAttribute("unit") == nil, "preview bound a real unit")
    local config = playerFrame.MSUFSpec.portrait
    assert(portrait.nativePortraitUnmasked == ((config.shape == "BLIZZARD") or nil), "preview dropped the native bust mode")
    local left, right, top, bottom = portrait:GetTexCoord()
    assert(left == config.texL and right == config.texR and top == config.texT and bottom == config.texB,
        "native portrait paint discarded the configured crop")
end
CheckLivePortrait()
for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PORTRAITS_UPDATED" }) do
    portraitRevision = portraitRevision + 1
    local draws = portrait.nativePortraitDraws
    for _ = 1, 3 do mw:Fire(event, "player") end
    mw:RunTimers()
    CheckLivePortrait()
    assert(portrait.nativePortraitDraws == draws + 1, "portrait events bypassed the preview refresh queue")
end
liveUnits.player = false
Preview.Refresh(playerBox, "TEST_FALLBACK")
assert(portrait.nativePortraitUnit == nil and portrait:GetTexture() == Preview.Model.UNIT_DATA.player.portraitTexture,
    "missing player kept native art instead of the preview sample")
liveUnits.player = true
player.portraitRender, player.portraitClassStyle = "CLASS", "RONDO_COLOR"
mw.core.UF.Config.Refresh()
Preview.Refresh(playerBox, "TEST_CLASS")
assert(portrait.nativePortraitUnit == nil and portrait:GetTexture() ~= "RTPortrait1", "class mode painted a live portrait")
-- 3D draws the model over a hidden image, and reopening the page (which runs
-- the preview's portrait normalizer) must keep the saved render.
player.portraitRender = "3D"
mw.core.UF.Config.Refresh()
Preview.Refresh(playerBox, "TEST_3D")
local model3D = playerFrame.MSUFPortraitHolder.model3D
assert(model3D and model3D:IsShown() and not portrait:IsShown(), "3D preview did not show the model")
assert(model3D.modelUnit == "player", "3D preview did not bind the live player")
assert(M.Open("uf_player") ~= false)
mw:RunTimers()
assert(env.MSUF_DB.player.portraitRender == "3D", "opening the preview rewrote the 3D render")
playerBox = assert(Preview.active)
playerFrame = playerBox._unitScene:Frame()
portrait = assert(playerFrame.portrait)
model3D = playerFrame.MSUFPortraitHolder.model3D
assert(model3D and model3D:IsShown() and not portrait:IsShown(), "reopened 3D preview lost the model")
-- The 3D backdrop: class tint at the unit's own opacity, painted under the model.
player.portraitBgEnabled, player.portraitBgColorMode, player.portraitBgAlpha = true, "CLASS", 40
mw.core.UF.Config.Refresh()
Preview.Refresh(playerBox, "TEST_3D_BG")
local bgSpec = playerFrame.MSUFSpec.portrait.bg
assert(bgSpec.enabled and bgSpec.mode == "CLASS" and bgSpec.dynamic == true and math.abs(bgSpec.a - 0.4) < 1e-9,
    "background mode or opacity did not compile")
local bg = playerFrame.MSUFPortraitHolder.bg
local sampleClass = playerFrame._msufPortraitSampleClass
local classColor = sampleClass and env.RAID_CLASS_COLORS and env.RAID_CLASS_COLORS[sampleClass]
assert(bg:IsShown() and model3D:IsShown(), "3D background or model missing")
if classColor then
    assert(bg._msufVertexR == classColor.r and bg._msufVertexB == classColor.b and math.abs(bg._msufVertexA - 0.4) < 1e-9,
        "3D background did not take the sample's class colour")
end
player.portraitBgColorMode = "BOGUS"
mw.core.UF.Config.Refresh()
Preview.Refresh(playerBox, "TEST_3D_BG_BOGUS")
assert(playerFrame.MSUFSpec.portrait.bg.mode == "CUSTOM", "unknown background mode did not fall back to custom")
player.portraitBgEnabled, player.portraitBgColorMode, player.portraitBgAlpha = nil, nil, nil
player.portraitRender = "2D"
mw.core.UF.Config.Refresh()
Preview.Refresh(playerBox, "TEST_2D")
assert(not model3D:IsShown(), "2D preview kept the model")
assert(not bg:IsShown(), "disabled background stayed on the preview")
CheckLivePortrait()

mw.world:EnterCombat()
portraitRevision = portraitRevision + 1
mw:Fire("UNIT_PORTRAIT_UPDATE", "player")
mw:RunTimers()
assert(portrait.nativePortraitRevision ~= portraitRevision, "portrait refreshed during combat")
mw.world:LeaveCombat()
mw:RunTimers()
assert(M.Open("uf_player") ~= false)
mw:RunTimers()
playerBox = assert(Preview.active)
playerFrame = playerBox._unitScene:Frame()
portrait = assert(playerFrame.portrait)
CheckLivePortrait()

local playerDriver = playerBox._msufLiveStateDriver
assert(playerDriver.portraitEventUnit_UNIT_PORTRAIT_UPDATE == "player", "player portrait event lost its unit filter")
if mw.core.Client.SupportsUnit("targettarget") then
    local target = env.MSUF_DB.targettarget
    target.portraitMode, target.portraitRender = "LEFT", "2D"
    liveUnits.targettarget = true
    mw.core.UF.Config.Refresh()
    assert(mw:Select("uf_targettarget"))
    local dependentBox = assert(Preview.active)
    assert(dependentBox.key == "targettarget", "dependent preview did not open")
    local driver = dependentBox._msufLiveStateDriver
    assert(driver:IsEventRegistered("UNIT_MODEL_CHANGED") and driver.portraitEventUnit_UNIT_MODEL_CHANGED == nil,
        "dependent preview filtered its model event by unit")
    local image = assert(dependentBox._unitScene:Frame().portrait)
    portraitRevision = portraitRevision + 1
    mw:Fire("UNIT_MODEL_CHANGED", "target")
    mw:RunTimers()
    assert(image.nativePortraitUnit == "targettarget" and image.nativePortraitRevision == portraitRevision,
        "dependent preview did not repaint its bound portrait")
end

local activeBox = Preview.active
local activeDriver = activeBox._msufLiveStateDriver
MW.FireVisibilityScripts(activeBox)
activeBox:Hide()
assert(not activeDriver:IsEventRegistered("PORTRAITS_UPDATED"), "hidden preview retained its portrait events")

print("preview_scene_input_contract_smoke " .. flavor .. ": font/sample/layer inputs and native portrait refresh")
