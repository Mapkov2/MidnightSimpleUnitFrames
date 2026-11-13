-- A full profile retains absent per-unit overrides and explicit values through import and reload.
local root, flavor = assert(arg[1]):gsub("\\", "/"), assert(arg[2])
local C = dofile(root .. "/tools/profile_corpus_golden.lua")
local function Login(saved)
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(world, saved)
    return world
end

local source, destination = Login({}), Login({})
local db = source.env.MSUF_DB
local function Read(world)
    return world.core.UF.Config.CompileSpec("target", {})
end
local factory = Read(source)
local x, y, layer, alpha = factory.status.elite.x, factory.status.elite.y, factory.status.elite.layer, factory.range.alpha
db.general.eliteIconOffsetX, db.general.eliteIconOffsetY, db.general.eliteIconLayer = 41, 11, 4
db.general.eliteIconSize = factory.status.elite.size + 9
db.general.rangeFadeAlpha = 0.67
db.target.eliteIconOffsetX, db.target.eliteIconOffsetY, db.target.eliteIconLayer = nil, 0, nil
db.target.eliteIconSize = factory.status.elite.size
db.target.rangeFadeEnabled, db.target.rangeFadeAlpha = false, nil

local function Check(world, expectedX)
    local target = world.env.MSUF_DB.target
    local spec = Read(world)
    assert(spec.status.elite.x == expectedX and spec.status.elite.y == 0 and spec.status.elite.layer == 4,
        "target elite icon lost inherited geometry or explicit zero")
    assert(spec.status.elite.size == factory.status.elite.size and spec.range.enabled == false,
        "explicit factory-equal size or disabled range fade was lost")
    assert(spec.range.alpha == 0.67, "target range opacity stopped inheriting the global setting")
    assert(target.eliteIconOffsetX == nil and target.eliteIconLayer == nil and target.rangeFadeAlpha == nil,
        "full-profile import converted inherited values to explicit overrides")
end
Check(source, 41)
local send, receive = source.core.PublicGlobals, destination.core.PublicGlobals
local ok, text = send.MSUF_ExportExternal(source.env.MSUF_ActiveProfile)
assert(ok and type(text) == "string")
assert(receive.MSUF_ImportExternal(text, "Transferred"))
assert(receive.MSUF_SwitchProfile("Transferred"))
Check(destination, 41)
receive.MSUF_EnsureDB(true)
destination.env.MSUF_DB.general.eliteIconOffsetX = 57
Check(destination, 57)
destination:FireEvent("PLAYER_LOGOUT")
local reloaded = Login({ MSUF_GlobalDB = C.Copy(destination.env.MSUF_GlobalDB), MSUF_DB = C.Copy(destination.env.MSUF_DB) })
Check(reloaded, 57)
local untouched = Read(Login({}))
assert(untouched.status.elite.x == x and untouched.status.elite.y == y and untouched.status.elite.layer == layer
    and untouched.range.alpha == alpha, "import changed the fresh profile defaults")
print("PASS " .. flavor .. " full profile keeps inherited target geometry and range opacity through reload")
