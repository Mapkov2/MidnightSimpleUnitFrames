-- A secret player name must not enter preview shortening or identity caches.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secretName = Secrets.New("string")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, "Mainline", { beforeBoot = function(world)
    world.env.MAX_BOSS_FRAMES = 5
    world.env.type, world.env.issecretvalue = type, issecretvalue
    local plain = world.env.UnitName
    world.env.UnitName = function(unit)
        local caller = debug.getinfo(2, "S")
        if caller.source:find("MSUF_UF_Group_Preview.lua", 1, true) then return secretName end
        return plain(unit)
    end
end })
local GF = h.GF
GF.EnsureDB()
local conf = GF.GetConf("party")
conf.enabled, conf.nameShortenMax = true, 3
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua"
local stop = Secrets.Watch(path)
h.env.MSUF2_GFPagePreviewActive = true
assert(GF.ShowPreview("party", 2))
h:RunTimers()
local name = GF._previewFrames.party[1]._msufPreviewNameText
assert(not issecretvalue(name) and type(name) == "string" and name ~= "", "preview retained a secret identity")
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("group_preview_secret_name_smoke: PASS")
