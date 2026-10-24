-- The Augmentation replacement must gloss its actual native duration fill.
local root, sourceOverride = assert(arg[1]), arg[2]
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, "Mainline", { page = "home", beforeCore = function(world)
    if not sourceOverride then return end
    local load = world.LoadFile
    world.LoadFile = function(self, path, ...)
        if path:sub(-#"MSUF_CP_EbonMight.lua") == "MSUF_CP_EbonMight.lua" then path = sourceOverride end
        return load(self, path, ...)
    end
end })
local core, env = mw.core, mw.env
local checks = 0
local function Check(ok, label) checks = checks + 1 assert(ok, label) end
local db = mw.M.EnsureDB()
db.general.powerGlossEnabled, db.general.powerGlossStrength = true, 0.7
core.UF.Config.Refresh()
local spec = core.UF.Config.GetSpec("player")
spec.power.alpha = 0.35
local frame = env.CreateFrame("Button", nil, env.UIParent)
frame.MSUFSpec = spec
local host = env.CreateFrame("StatusBar", nil, frame)
host:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
host:SetMinMaxValues(0, 1)
host:SetValue(0) -- the ordinary Power carrier deliberately paints nothing
frame.targetPowerBar = host
local CP = { _pf = frame }
local builders = env.MSUF_CP_CORE_BUILDERS
local surface = builders.CONTROLLER_SURFACE({ CP = CP, _cpDB = { colorByType = false, bars = {} },
    CPConst = env.MSUF_CP_CONST, ResolveClassPowerColor = function() return 1, 1, 1 end,
    CP_ResolveTexture = function(texture) return texture end })
Check(surface.GetEbonStyle().barGloss == spec.power.barGloss, "Player Power compiled gloss was not propagated to Ebon style")
local denied, secret, handoffs = false, false, 0
local sealed = {}
local function Seal(region)
    if not region or sealed[region] then return end
    sealed[region] = true
    region.CanBeAccessedInContext = function() return not denied end
    for name, method in pairs(mw.world.widgets.Methods) do
        if name ~= "CanBeAccessedInContext" and type(method) == "function" then
            local original = region[name]
            region[name] = function(self, ...)
                if denied then error("forbidden native duration subtree: " .. name) end
                return original(self, ...)
            end
        end
    end
end
env.C_Secrets.ShouldAurasBeSecret = function() return secret end
-- MSUF_Auras3 is a namespace-only export: the table the class power builders read lives in the registry.
core.PublicGlobals.MSUF_Auras3.CreateClassPowerAuraSensor = function(parent, _, _, initialize)
    local sensor = env.CreateFrame("Frame", nil, parent)
    local button = env.CreateFrame("Frame", nil, sensor)
    button.SetDurationBar = function(_, native)
        handoffs = handoffs + 1
        Check(CP.ebonGloss and CP.ebonGloss.target == native:GetStatusBarTexture(),
            "gloss was not installed before native duration handoff")
        Check(CP.ebonGloss.upper:GetAlpha() == 0.35, "native duration gloss ignored Player Power opacity")
    end
    button.SetDurationText = function() end
    spec.power.barGloss.strength = 0.13
    initialize(button)
    Check(CP.ebonGloss.upper._msufGlossStrength == 0.7, "native initialization aliased a changed style snapshot")
    spec.power.barGloss.strength = 0.7
    Seal(button) Seal(CP.ebonNativeBar) Seal(CP.ebonNativeText)
    Seal(CP.ebonGloss and CP.ebonGloss.upper) Seal(CP.ebonGloss and CP.ebonGloss.lower)
    return sensor
end
local api = builders.EBON_MIGHT({ CP = CP, EBON = { SPELL_ID = 395296 }, CreateFrame = env.CreateFrame,
    GetHost = function() return host end, GetStyle = surface.GetEbonStyle, GetTextLevel = function() return 5 end })
Check(api.SetActive(true) and handoffs == 1, "native Ebon duration slot was not initialized")
local gloss = assert(CP.ebonGloss)
Check(gloss.target ~= host:GetStatusBarTexture(), "gloss remained attached to the empty carrier")
Check(gloss.upper:IsShown() and gloss.lower:IsShown(), "native duration gloss is hidden")
Check(gloss.upper._msufGlossStrength == 0.7, "native duration gloss strength differs")
-- Captured profile snapshots do not alias later mutations, and existing legal
-- mutable refresh applies the next style without recreating native regions.
spec.power.barGloss.strength = 0.2
Check(gloss.upper._msufGlossStrength == 0.7, "profile mutation altered captured native style")
Check(api.RefreshStyle(), "mutable native restyle failed")
Check(CP.ebonGloss == gloss and gloss.upper._msufGlossStrength == 0.2, "native strength refresh replaced or ignored gloss")
-- No widget calls may escape the existing forbidden/secret/combat refusal.
denied, secret = true, true
mw.world.widgets:SetCombat(true)
spec.power.barGloss.strength = 0.9
local ok, err = pcall(api.RefreshStyle)
Check(ok and CP.ebonStyleRetryPending == true, "denied native restyle touched forbidden subtree: " .. tostring(err))
Check(gloss.upper._msufGlossStrength == 0.2, "denied native restyle changed material")
mw.world.widgets:SetCombat(false)
ok, err = pcall(api.RefreshStyle)
Check(ok and CP.ebonStyleRetryPending == true, "secret native restyle was not deferred: " .. tostring(err))
denied, secret = false, false
Check(api.RefreshStyle() and not CP.ebonStyleRetryPending, "existing mutable retry did not complete")
Check(CP.ebonGloss == gloss and gloss.upper._msufGlossStrength == 0.9 and handoffs == 1,
    "native retry lost gloss state or recreated the sensor")
spec.power.barGloss.enabled = false
Check(api.RefreshStyle() and not gloss.upper:IsShown() and not gloss.lower:IsShown(), "native gloss disable did not hide retained bands")
spec.power.barGloss.enabled, spec.power.barGloss.strength = true, 0
Check(api.RefreshStyle() and not gloss.upper:IsShown(), "native strength zero remained visible")
print("bar gloss Ebon smoke: PASS (" .. checks .. " checks; actual duration fill and denied native subtree)")
