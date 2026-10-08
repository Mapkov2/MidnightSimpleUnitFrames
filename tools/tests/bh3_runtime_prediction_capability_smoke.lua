local root=assert(arg[1])
local World=dofile(root.."/tools/tests/client_world.lua")
for _,flavor in ipairs({"Mainline","Forever","Vanilla","TBC","Mists"}) do
 local w=World.New(root,flavor);w:Boot();assert(not w:FirstFailure(),"boot "..flavor)
 assert(w.core.Client.SupportsClassResourceSetting("bars.showResourcePrediction")== (flavor=="Mainline" or flavor=="Mists"),"prediction capability wrong for "..flavor)
 print("PASS prediction capability "..flavor)
end
