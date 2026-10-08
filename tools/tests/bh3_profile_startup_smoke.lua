-- Login binds ownership before LibDBIcon can retain the saved legacy copy.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local mode = arg[3] or "minimap"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world.env.MAX_TOTEMS, world.env.MAX_BOSS_FRAMES = 4, 5
world.env.TotemFrame = false -- this profile-ownership test has no native totem widget
local registered, registrations = {}, 0
local load = world.LoadFile
function world:LoadFile(path, addon, ns)
    local ok, message = load(self, path, addon, ns)
    if path:match("/Libs/LibStub/LibStub%.lua$") then
        local LS = rawget(self.env, "LibStub")
        local ldb = LS:NewLibrary("LibDataBroker-1.1", 4)
        function ldb:NewDataObject(_, object) return object end
        local icon = LS:NewLibrary("LibDBIcon-1.0", 55)
        function icon:IsRegistered(name) return registered[name] ~= nil end
        function icon:Register(name, _, db) registered[name] = {db=db}; registrations=registrations+1 end
        function icon:Refresh(name, db) registered[name].db=db end
        function icon:Show() end
        function icon:Hide() end
    end
    return ok, message
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local A = {_msufProfileSchema=600, general={menuLocale="deDE",showMinimapIcon=true,minimapIconDB={minimapPos=220}}}
local Default = {_msufProfileSchema=600, general={showMinimapIcon=true,minimapIconDB={minimapPos=220}}}
local saved = {_msufProfileSchema=600, general={menuLocale="deDE",showMinimapIcon=true,minimapIconDB={minimapPos=220}}}
local global = {profiles={A=A,Default=Default},char={},global={}}
world:LoadSavedVariables("MidnightSimpleUnitFrames", {MSUF_DB=saved,MSUF_GlobalDB=global})
if mode == "locale" then
    assert(world.core.LOCALE == "enUS", "new character inherited the previous character's locale")
    local name, profile = world.core.ResolveStartupProfile(global, saved, "Tester-Realm")
    assert(name == "Default" and profile == Default)
    global.global.defaultProfileForNewChars="A"
    name, profile = world.core.ResolveStartupProfile(global, saved, "Tester-Realm")
    assert(name == "A" and profile == A)
    global.char["Tester-Realm"]={activeProfile="Missing"}
    name, profile = world.core.ResolveStartupProfile(global, saved, "Tester-Realm")
    assert(name == "Missing" and profile == Default, "repair donor differs from locale donor")
    global.profiles={}; global.char={}
    name, profile = world.core.ResolveStartupProfile(global, saved, "Tester-Realm")
    assert(name == "Default" and profile == saved, "legacy-only profile lost its locale")
else
    -- Force the minimap listener to run before the later profile-bind owner.
    for _, frame in ipairs(world.widgets.frames) do
        local fn = frame:GetScript("OnEvent")
        if fn and frame:IsEventRegistered("PLAYER_LOGIN") and debug.getinfo(fn,"S").source:find("MSUF_MinimapButton.lua",1,true) then
            fn(frame,"PLAYER_LOGIN")
        end
    end
    world.env.MSUF_InitProfiles()
    local reg=assert(registered.MidnightSimpleUnitFrames,"minimap never registered after profile bind")
    assert(reg.db == world.env.MSUF_DB.general.minimapIconDB, "minimap retained detached SavedVariables")
    reg.db.minimapPos=45
    assert(Default.general.minimapIconDB.minimapPos==45 and saved.general.minimapIconDB.minimapPos==220)
    -- Keep real profile rebinding and minimap callbacks; unit rendering is
    -- a separate integration surface with native widget methods of its own.
    world.env.MSUF_UFCore_NotifyConfigChanged = function() end
    world.env.MSUF_GF_RebuildAll = function() end
    world.env.MSUF_ClassPower_Apply = function() end
    global.char["Tester-Realm"]={activeProfile="A"}
    world.env.MSUF_InitProfiles()
    assert(reg.db == world.env.MSUF_DB.general.minimapIconDB and world.env.MSUF_ActiveProfile=="A")
    reg.db.minimapPos=90
    assert(A.general.minimapIconDB.minimapPos==90 and Default.general.minimapIconDB.minimapPos==45)
    assert(registrations==1,"profile bind recreated the minimap button")
end
print("profile startup "..mode..": "..flavor.." passed")
