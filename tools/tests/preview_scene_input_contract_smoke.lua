-- preview_scene_input_contract_smoke.lua <root> <flavor> [source-overlay] [budget]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local activeNative, nativeCalls = false, 0
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
print("preview_scene_input_contract_smoke " .. flavor .. ": font/sample/layer inputs survive scene repaint")
