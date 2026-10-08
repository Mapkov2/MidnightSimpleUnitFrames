-- Behavior regressions for profile ownership and runtime state transitions.
local root = assert(arg[1], "repo root required")
local failed, passed = 0, 0
local function Read(path)
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/" .. path, "rb"))
    local s = file:read("*a"); file:close()
    return s:gsub("\r\n", "\n"):gsub("^\239\187\191", "")
end
local function Slice(path, first, last)
    local s = Read(path)
    local start = assert(s:find(first, 1, true), first)
    local stop = assert(s:find(last, start + #first, true), last)
    return s:sub(start, stop - 1)
end
local function Compile(source, env)
    env = setmetatable(env or {}, { __index = _G })
    local fn = assert(loadstring(source))
    setfenv(fn, env)
    return fn, env
end
local function Check(id, fn)
    local ok, message = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. id)
    else failed = failed + 1; print("FAIL " .. id .. ": " .. tostring(message)) end
end
Check("CX1-04", function()
    local f = Compile(Slice("State/MSUF_Defaults.lua", "local function MSUF_Defaults_MigrateUnitDispelOwnership", "local function MSUF_Defaults_NormalizeFontKey") .. "return MSUF_Defaults_MigrateUnitDispelOwnership", {MSUF_DEFAULTS_UNIT_DISPEL_KEYS={"enabled"}})()
    local db={general={enabled=true},player={hlOverride=true,enabled=false},target={enabled=false}}
    f(db); assert(db.player.enabled == false); assert(db.target.enabled == true)
end)
Check("CX1-09", function()
    local archive={A={old=true}}
    local f=Compile(Slice("State/MSUF_FirstLoad.lua", "local function StoreArchivedProfile", "local function ArchivePre6Profiles") .. "return StoreArchivedProfile", {EnsurePre6Archive=function() return archive end})()
    local second={}; f("A",second); f("A",second)
    assert(archive.A.old and archive["A (2)"]==second and archive["A (3)"]==nil)
end)
Check("C03-A1", function()
    for _,locale in ipairs({"koKR","zhCN","zhTW","enUS"}) do
        local native={general={fontKey="Expressway",menuFontKey="Expressway"}}
        local env={MSUF={Client={IsForever=true}},MSUF_FACTORY_DEFAULT_PROFILE_COMPACT="payload",
          MSUF_Defaults_DeepCopy=function(out,input) out.general={fontKey=input.general.fontKey,menuFontKey=input.general.menuFontKey} end,
          MSUF_Defaults_GetGlobalFontDefault=function() return locale end,
          MSUF_Defaults_GetMenuFontDefault=function() return "menu_"..locale end}
        env._G={MSUF_TryDecodeCompactString=function() return {addon="MSUF",fmt=2,msuf6={schema=600,payload=native}} end}
        local source=Read("State/MSUF_Defaults.lua")
        local start=assert(source:find("local function MSUF_Defaults_CreateFactoryProfile()",1,true))
        local stop=assert(source:find("\nend",start,true))
        local f=Compile(source:sub(start,stop+3).."\nreturn MSUF_Defaults_CreateFactoryProfile",env)()
        local result=f(); assert(result.general.fontKey==locale and result.general.menuFontKey=="menu_"..locale)
        assert(native.general.fontKey=="Expressway", "factory source mutated")
    end
end)
Check("C28-A10", function()
    local groups={{name="Group"}}; local global={profileSyncGroups=groups}
    local f=Compile(Slice("State/MSUF_ProfileSync.lua", "local function Groups()", "function Sync.Validate").."return Groups",{MSUF_GlobalDB={global=global},Sanitize=function() return {{name="Group"}},false end})()
    assert(f()==groups and f()[1]==groups[1], "read invalidates live navigation tokens")
end)
Check("C02-A1", function()
    local env={_G={MSUF_GlobalDB={global={}}},time=function() return 7 end}
    local f=Compile(Read("State/MSUF_GuidedTour.lua"),env); local ns={};f("MSUF",ns)
    local state=ns.GuidedTour6:GetState();state.profileName="A"
    ns.GuidedTour6:RenameProfile("A","B"); assert(state.profileName=="B")
    ns.GuidedTour6:RenameProfile("Other","C");assert(state.profileName=="B")
end)
Check("MT8-A1", function()
    local f=Compile(Slice("State/MSUF_Profiles.lua", "function MSUF_GetPlayerSpecID()", "--- Combat-safe deferrer").."return MSUF_GetPlayerSpecID",{MSUF={Specialization={GetSpecialization=function() return 2 end,GetSpecializationInfo=function(i) assert(i==2);return 270 end}}})()
    assert(f()==270,"namespaced specialization missing")
end)
Check("CX1-08", function()
    local hides=0;local tip={IsForbidden=function() return false end,IsShown=function() return true end,Hide=function() hides=hides+1 end}
    local fn=Compile(Slice("Runtime/MSUF_UnitTooltips.lua", "local function MSUF_ClearTrackedGameTooltip", "if _G.GameTooltip and").."return MSUF_ClearTrackedGameTooltip",{_G={GameTooltip=tip}})()
    local owner={};fn(owner,false);fn(owner,true);assert(hides==0,"unowned tooltip hidden")
    tip._msufUnitTooltipOwner=owner;fn({},false);assert(hides==0);fn(owner,false);assert(hides==1)
end)
Check("CX1-07", function()
    local src=Slice("State/MSUF_Profiles.lua", "function ImportTx.Merge(kind, payload, db)", "    elseif kind == \"groupframe\" then").."\n    end\nend\nreturn ImportTx.Merge"
    local f=Compile(src,{ImportTx={},MSUF_GeneralKeysOfKind=function() return {} end,MSUF_WipeGeneralSubset=function() end,MSUF_ApplyGeneralSubset=function() end,MSUF_DeepCopy=function(x)return x end,MSUF_WipeTable=function(t)for k in pairs(t)do t[k]=nil end end})()
    local db={gameplay={key=1},classColors={key=2},npcColors={key=3},target={key=0}}
    f("unitframe",{gameplay={key=99},classColors={},npcColors={},target={key=7}},db)
    assert(db.gameplay.key==1 and db.classColors.key==2 and db.npcColors.key==3 and db.target.key==7)
end)
Check("C03-A2", function()
    local f=Compile(Slice("Runtime/MSUF_Colors.lua", "local function GetGlobalFontColor()", "local function SetGlobalFontColor").."return GetGlobalFontColor",{_general=function()return {fontColor="red"}end,MSUF_FONT_COLORS={red={1,.2,.3}}})()
    local r,g,b=f();assert(r==1 and g==.2 and b==.3)
end)
Check("C03-A3", function()
    local source=Slice("Runtime/MSUF_FontRegistry.lua", "local FONT_LIST = {", "\ndo\n")
    local list=Compile(source.."return FONT_LIST")()
    for _,font in ipairs(list) do if font.key=="ARIALN" then assert(font.path=="Fonts\\ARIALN.TTF");return end end
    error("Arial absent")
end)
Check("C04-A3", function()
    local shown,hidden=0,0
    local f=Compile(Slice("Features/Gameplay/MSUF_Feature_GameplayRuntime.lua","local function CombatStateClearTimerFired()","local function CancelCombatStateClear").."return CombatStateClearTimerFired",{stateText={},GetGameplayDB=function()return {enableCombatStateText=true,lockCombatState=false}end,ClearCombatStateText=function()hidden=hidden+1 end,SetCombatStateClickThrough=function()end,MSUF={Util={InCombat=function()return true end}},MSUF_GetCombatStateColors=function()end,TextOrDefault=function()end,ShowCombatStateText=function()shown=shown+1 end})()
    f();assert(hidden==1 and shown==0,"combat handle reappeared")
end)
Check("C14-A1", function()
    local hidden=0;local env={A3={},IsConfigBlocked=function()return true end,UnitPreviewActive=function()return false end,EM={HideUnit=function()hidden=hidden+1 end,HideAll=function()hidden=hidden+1 end}}
    Compile(Slice("Auras3/MSUF_Auras3_EditMode.lua","function A3.RefreshEditPreview(unit)","--- Advances only"),env)()
    env.A3.RefreshEditPreview("boss");assert(hidden==1,"combat left preview visible")
end)
Check("C13-A2", function()
    local state={};local env={A3={_EnsureGroupAuraPresenceState=function()return state end,_CommitGroupAuraPresenceState=function()return true end},_G={UnitIsConnected=function()return false end},issecretvalue=function()return false end}
    Compile(Slice("Auras3/Runtime/MSUF_Auras3_Runtime_Presence.lua","A3._UpdateGroupAuraPresenceConnectionState = function(","A3._UpdateGroupAuraPresenceState = function("),env)()
    env.A3._UpdateGroupAuraPresenceConnectionState("party1");assert(state.offline==true)
end)
assert(failed==0,tostring(failed).." regression cases failed ("..passed.." passed)")
print("bh3 runtime state: "..passed.." passed")
