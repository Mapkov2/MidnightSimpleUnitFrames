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

local World=dofile(root.."/tools/tests/client_world.lua")
local function WorldWithNativeSpecs(flavor)
 local w=World.New(root,flavor)
 w.env.GetSpecialization=false;w.env.GetSpecializationInfo=false
 w.env.C_SpecializationInfo={GetSpecialization=function()return 1 end,GetSpecializationInfo=function()return 65,"Heilig" end,GetNumSpecializations=function()return 3 end}
 w.env.UnitClass=function()return "Paladin","PALADIN" end
 w.env.UnitExists=function()return true end;w.env.UnitIsPlayer=function()return true end
 w.env.UnitLevel=function()return 90 end;w.env.UnitRace=function()return "Mensch" end;w.env.UnitSex=function()return 2 end
 w.env.UnitFactionGroup=function()return "Alliance","Allianz" end;w.env.UnitIsPVP=function()return false end
 w:Boot();assert(not w:FirstFailure(),"boot failed")
 return w
end
Check("MT8-A2",function()
 local w=WorldWithNativeSpecs("Mists")
 assert(w.core.Gameplay.GetPlayerSpecID()==65,"crosshair helper misses native spec")
end)
Check("MT8-A3",function()
 local w=WorldWithNativeSpecs("Mainline")
 assert(w.core.GF.SpellIndicators.GetPlayerSpec()=="HolyPaladin","group indicators miss native spec")
end)
local function ReplaceUpvalue(f,name,value)
 for i=1,100 do local n=debug.getupvalue(f,i);if not n then break end;if n==name then debug.setupvalue(f,i,value);return true end end
 return false
end
local function TooltipLines()
 local w=WorldWithNativeSpecs("Mists")
 local f=assert(w.env.MSUF_ShowUnitInfoTooltip)
 local lines
 assert(ReplaceUpvalue(f,"MSUF_GetPlayerInfoFrame",function()return {}end))
 ReplaceUpvalue(f,"MSUF_UnitInfo_BuildNameLine",function()return "Name"end)
 ReplaceUpvalue(f,"MSUF_UnitInfo_BuildLine2_Player",function()return "Player"end)
 ReplaceUpvalue(f,"MSUF_UnitInfo_GetLocationText",function()return "Zone"end)
 assert(ReplaceUpvalue(f,"MSUF_UnitInfo_ShowFrame",function(_,...)lines={...}end))
 f("player")
 return lines
end
Check("MT8-A4",function()assert(TooltipLines()[3]=="Heilig Paladin","tooltip spec absent")end)
Check("CX1-03",function()assert(TooltipLines()[4]:find("Allianz",1,true),"tooltip faction is English token")end)
Check("MT8-A5",function()
 local e={C_SpellBook={IsSpellKnownOrInSpellBook=function(id)return id==1219723 end},issecretvalue=function()return false end,
 ActiveSpellID=function()return 356995 end,PlainNumber=function(n)return n end,CHANNEL_TICK_DATA={[356995]={ticks=4,modSpell=1219723,modTicks=5}},MAX_AUTO_TICK_COUNT=12}
 e._G=e
 local f=Compile(Slice("Castbars/MSUF_CastbarChannelTicks.lua","local function PlayerKnowsSpell","local function TickConfig").."return AutomaticMarkerLayout",e)()
 local lines,ticks=f({});assert(lines==4 and ticks==5,"known modern talent not reflected in channel markers")
end)
Check("L07-A2",function()
 local w=World.New(root,"Mainline");w.env.AbbreviateNumbers=function()return "12.3K"end;w:Boot();assert(not w:FirstFailure())
 w.env.MSUF_DB={general={numberAbbrevStyle="COMPACT"}}
 w.core.NumberFormat.Refresh();assert(w.core.NumberFormat.GetStyle()=="COMPACT")
 w.env.MSUF_DB=nil;w.env.MSUF_ActiveProfile=nil
 local char=w.env.MSUF_GetCharKey()
 w.env.MSUF_GlobalDB={global={},profiles={Default={general={numberAbbrevStyle="GAME"}}},char={[char]={activeProfile="Default"}}}
 w.env.MSUF_InitProfiles()
 assert(w.core.NumberFormat.GetStyle()=="GAME","first active DB bind retained old abbreviation style")
end)
Check("C08-A1",function()
 local w=World.New(root,"Forever");w.env.WOW_PROJECT_CAMELOT=99;w.env.WOW_PROJECT_ID=99;w:Boot();assert(not w:FirstFailure())
 assert(w.core.Client.DescribeLines()[1]:find("WOW_PROJECT_CAMELOT",1,true),"known Forever project labeled unrecognized")
end)
print(string.format("bh3_runtime_compat: %d passed, %d failed",passed,failed));assert(failed==0)
