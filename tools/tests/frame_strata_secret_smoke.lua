-- Build 1.60.1.70291: GetFrameStrata has SecretReturns.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
for _, flavor in ipairs({ "Mainline", "Forever", "TBC" }) do
    local world = World.New(root, flavor)
    Secrets.Install()
    world.env.type, world.env.issecretvalue = type, issecretvalue
    local env = world.env
    local totem = world.widgets:CreateFrame("Frame", "TotemFrame", world.widgets.UIParent)
    function totem.Update() end
    function totem.Layout() end
    env.TotemFrame = totem
    world:Boot()
    assert(not world:FirstFailure(), flavor .. ": addon boot failed")
    env.MSUF_EnsureDB()
    local ns = world.core
    local anchor = world.widgets:CreateFrame("Frame", nil, world.widgets.UIParent)
    env.MSUF_player = anchor
    local castbar = world.widgets:CreateFrame("Frame", nil, world.widgets.UIParent)
    castbar.unit = "player"
    ns.UF.GetFrame = function() return anchor end
    local setters = 0
    for _, frame in ipairs({ totem, castbar }) do
        frame.SetFrameStrata = function(self, value)
            assert(not Secrets.IsSecret(value), "secret strata reached an addon write")
            setters = setters + 1
            self.frameStrata = value
        end
    end
    local stop = Secrets.Watch({
        root .. "/MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_TotemPreview.lua",
        root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua",
    }, { strict = true })
    local g = assert(ns.MSUF_GetGameplayDBFast or ns.MSUF_EnsureGameplayDefaults)()
    -- A hidden original strata cannot be restored. Public anchor strata still wins.
    totem.frameStrata = Secrets.New("string")
    anchor.frameStrata = "HIGH"
    g.enablePlayerTotems = true
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    assert(totem.frameStrata == "HIGH", "public anchor strata was not adopted")
    g.enablePlayerTotems = false
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    assert(totem.frameStrata == "HIGH", "secret original strata was restored")
    -- A secret anchor cannot override the original public totem strata.
    totem.frameStrata = "LOW"
    anchor.frameStrata = Secrets.New("string")
    g.enablePlayerTotems = true
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    assert(totem.frameStrata == "LOW", "secret anchor changed the totem strata")
    g.enablePlayerTotems = false
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    assert(totem.frameStrata == "LOW", "public original strata was not restored")
    -- Secret current/anchor getters and missing anchors use public defaults.
    for _, unit in ipairs({ "player", "target", "boss", "arena" }) do
        castbar.unit = unit
        castbar.frameStrata = Secrets.New("string")
        env.MSUF_ApplyCastbarFrameLayer(castbar, {}, unit)
        assert(castbar.frameStrata == ((unit == "boss" or unit == "arena") and "HIGH" or "MEDIUM"),
            "secret castbar strata did not use its unit fallback")
    end
    anchor.frameStrata = "LOW"
    castbar.frameStrata = Secrets.New("string")
    env.MSUF_ApplyCastbarFrameLayer(castbar, {}, "player")
    assert(castbar.frameStrata == "LOW", "castbar did not share its public anchor strata")
    local before = setters
    env.MSUF_ApplyCastbarFrameLayer(castbar, {}, "player")
    assert(setters == before, "unchanged public strata caused a redundant write")
    local violations = stop()
    assert(#violations == 0, table.concat(violations, "\n"))
    print("Frame strata secrets: " .. flavor .. " takeover/restore and castbar layering passed")
end
