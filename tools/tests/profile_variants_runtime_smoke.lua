local root=assert(arg[1])
local NS={Client={SupportsEvent=function() return true end}}
local combat=false
local location,spec,group="none",63,false
function InCombatLockdown() return combat end
function IsInInstance() return location~="none",location end
function IsInGroup() return group end
function MSUF_GetPlayerSpecID() return spec end
local frames={}
function CreateFrame()
    local f={events={}}
    function f:SetScript(_,fn) self.event=fn end
    function f:RegisterEvent(e) self.events[e]=true end
    function f:UnregisterAllEvents() self.events={} end
    frames[#frames+1]=f
    return f
end
for _,file in ipairs({"MSUF_ProfileFields","MSUF_ProfileVariants","MSUF_ProfileVariantsRuntime"}) do
    assert(loadfile(root.."/MidnightSimpleUnitFrames/State/"..file..".lua"))("MSUF",NS)
end
local V=NS.ProfileVariants
local applies=0
NS.ProfileRuntime={Apply=function() applies=applies+1;V.ResolveCurrent() end}
MSUF_DB={general={darkMode=true},player={width=120}}
V.ResolveCurrent()
assert(#frames==0,"no variants means no event driver")
assert(V.Replace(MSUF_DB,{version=1,entries={
    {name="Dungeon",conditions={context="party"},patch={{path={"player","width"},value=200}}},
    {name="Dark",conditions={dark=true},patch={{path={"general","darkMode"},value=false}}},
}}))
assert(MSUF_DB.general.darkMode==false,"dark variant materialized")
local driver=assert(frames[1])
assert(driver.events.PLAYER_LOGOUT and driver.events.GROUP_ROSTER_UPDATE)
local before=applies
driver.event(driver,"GROUP_ROSTER_UPDATE")
assert(applies==before,"dark base condition stable; no repeated apply")
combat=true;location="party"
driver.event(driver,"ZONE_CHANGED_NEW_AREA")
assert(applies==before and driver.events.PLAYER_REGEN_ENABLED,"context deferred")
location="raid";driver.event(driver,"ZONE_CHANGED_NEW_AREA")
combat=false;driver.event(driver,"PLAYER_REGEN_ENABLED")
-- The latest context (raid) matches the same entries as before combat, so the
-- overlay is already right and no apply runs (review F7: matched-entry set).
assert(applies==before and MSUF_DB.player.width==120,"defer resolves latest context")
combat=true;location="party";driver.event(driver,"ZONE_CHANGED_NEW_AREA")
combat=false;driver.event(driver,"PLAYER_REGEN_ENABLED")
assert(applies==before+1 and MSUF_DB.player.width==200,"a deferred change of the matching entries applies once after combat")
location="party";driver.event(driver,"ZONE_CHANGED_NEW_AREA")
assert(MSUF_DB.player.width==200)
local inactive={general={},player={width=50}}
assert(V.Replace(inactive,{version=1,entries={{name="Other",patch={{path={"player","width"},value=70}}}}}))
assert(MSUF_DB.player.width==200,"editing inactive profile does not peel active overlay")
driver.event(driver,"PLAYER_LOGOUT")
assert(MSUF_DB.player.width==120 and MSUF_DB.general.darkMode==true,"logout persists base")
assert(V.Replace(MSUF_DB,nil))
assert(next(driver.events)==nil,"last variant removed unregisters all events")
print("profile_variants_runtime_smoke: OK")
