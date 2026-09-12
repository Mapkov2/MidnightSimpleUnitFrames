-- Explicit test doubles for runtime services outside a UI/DB fixture's scope.
-- Unknown symbols stay nil; this is not a permissive global fallback.
local Ports = { calls = {} }
function Ports.Install(names)
    for name in names:gmatch("%S+") do
        if _G[name] == nil then
            _G[name] = function(...)
                Ports.calls[#Ports.calls + 1] = { name = name, args = { ... } }
                return true
            end
        end
    end
end
Ports.Install("MSUF_BumpCastbarStyleRevision MSUF_Profiles_SetExportBlizzardEditMode MSUF_Profiles_SetImportBlizzardEditMode MSUF_ForceReanchorAllUnitFrames_Once")
return Ports
