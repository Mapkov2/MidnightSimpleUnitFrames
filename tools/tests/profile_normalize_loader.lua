-- profile_normalize_loader.lua -- the real profile normalizer for harnesses that
-- load the Auras3 menu model.
--
-- The model's Group Aura filter code (Auras3/MenuModel/MSUF_Auras3_Menu_GroupFilters.lua)
-- reads the stored-token check from MSUF.ProfileNormalize, which State loads long
-- before it (State/MSUF_ProfileNormalize.lua owns the list of filter tokens a
-- stored profile may keep). A harness that loads the model without the State
-- layer installs the three State files that normalizer needs, unchanged; a file
-- whose export the harness already loaded itself is not loaded a second time:
--
--   local Normalizer = assert(loadfile(root .. "/tools/tests/profile_normalize_loader.lua"))()
--   Normalizer.Install(root, namespace)   -- before the first menu model file
--
-- A namespace without an ExportPublic gets a publishing-nothing one while the
-- files load and is left without it afterwards, so the harness's own export
-- fallbacks keep working.
--
-- Plain Lua 5.1.

local Loader = {}

-- { file, the namespace field it publishes }
Loader.FILES = {
    { "State/MSUF_StateHelpers.lua", "StateHelpers" },
    { "State/MSUF_ProfileCodec.lua", "ProfileIOImportLimits" },
    { "State/MSUF_ProfileNormalize.lua", "ProfileNormalize" },
}

function Loader.Install(root, ns)
    root = tostring(root):gsub("\\", "/"):gsub("/+$", "")
    if type(ns.ProfileNormalize) == "table" then return ns end
    local lent = type(ns.ExportPublic) ~= "function"
    if lent then ns.ExportPublic = function(_, value) return value end end
    for _, entry in ipairs(Loader.FILES) do
        if ns[entry[2]] == nil then
            assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. entry[1]))("MidnightSimpleUnitFrames", ns)
        end
    end
    if lent then ns.ExportPublic = nil end
    assert(type(ns.ProfileNormalize) == "table", "the profile normalizer did not publish MSUF.ProfileNormalize")
    return ns
end

return Loader
