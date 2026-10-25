-- preview_classic_glow_fallback_smoke.lua <root> <Classic flavor> [original-source-root]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", beforeCore = function(world)
    if not arg[3] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_GroupPreview_Render.lua$") or path:match("Game/Classic/Auras/MSUF_Auras3_Visuals.lua$") then
            path = arg[3] .. path:sub(#root + 1)
        end
        return load(self, path, addon, ns)
    end
end })
assert(mw.core.Client.IsClassic)
local Stage
for i = 1, 60 do
    local name, value = debug.getupvalue(mw.M.GroupPreviewRender.Install, i)
    if not name then break end
    if name == "Stage" then Stage = value end
end
assert(Stage, "group composition stages missing")
local env, core = mw.env, mw.core
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame:SetSize(250, 50)
frame.MSUFSpec = {}
local mock = env.CreateFrame("Frame", nil, env.UIParent)
mock._cell = frame
local handle = env.CreateFrame("Frame", nil, mock)
local placed = { type = "icon", size = 24, iconEffect = "glow" }
local st = { kind = "party", mock = mock, previewScale = 1, conf = { spellIndicators = { style = {} } },
    scene = { spellIconScale = 1, selectedSpellCfg = {}, selectedPlaced = placed },
    env = { CurrentSpellTexture = function() return 134400 end, CurrentSpellColor = function() return .2, .4, .6 end },
    SetPreviewFont = function() end }
-- The generic boot world stubs unresolved globals. This missing function must
-- stay absent here, matching the real Classic client rather than that stub.
rawset(env, "ShowPreviewGlow", nil)
local meta = getmetatable(env)
local previousIndex = meta.__index
meta.__index = function(self, key)
    if key == "ShowPreviewGlow" then return nil end
    if type(previousIndex) == "function" then return previousIndex(self, key) end
    return previousIndex and previousIndex[key]
end
Stage.ConfigureSelectedSpellHandle(st, handle)
local visual = assert(handle._msufEngineVisual)
local glow = assert(visual._msufA3ClassicIconGlow, "Classic glow painter was not used")
assert(glow:IsShown(), "Classic fallback glow is hidden")
local frames, regions = mw:Frames(), #visual.regions
for _ = 1, 5 do Stage.ConfigureSelectedSpellHandle(st, handle) end
assert(mw:Frames() == frames and #visual.regions == regions, "Classic glow was recreated")
placed.iconEffect = "none"
Stage.ConfigureSelectedSpellHandle(st, handle)
assert(not glow:IsShown(), "turning off the effect left a glow")
local sceneRoot = core.GF.NewPreviewScene(env.UIParent)
sceneRoot:Activate()
local scene = sceneRoot:Unit("player", { sample = { frameEffect = { kind = "BORDER", color = { .2, .4, .6, 1 } } } })
assert(scene:Show() ~= false, "new Classic icon provider broke the frame effect contract")
sceneRoot:Deactivate()
print("preview_classic_glow_fallback_smoke " .. flavor .. ": fallback, reuse and cleanup passed")
