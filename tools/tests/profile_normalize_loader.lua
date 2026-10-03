-- profile_normalize_loader.lua -- the real profile normalizer for harnesses that
-- load the Auras3 menu model.
--
-- The model's Group Aura filter code (Auras3/MenuModel/MSUF_Auras3_Menu_GroupFilters.lua)
-- reads the stored-token check from MSUF.ProfileNormalize, which State loads long
-- before it (State/MSUF_ProfileNormalize.lua owns the list of filter tokens a
-- stored profile may keep). A harness that loads the model without the State
-- layer installs the three State files that normalizer needs, unchanged:
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

Loader.FILES = {
    "State/MSUF_StateHelpers.lua",
    "State/MSUF_ProfileCodec.lua",
    "State/MSUF_ProfileNormalize.lua",
}

function Loader.Install(root, ns)
    root = tostring(root):gsub("\\", "/"):gsub("/+$", "")
    if type(ns.ProfileNormalize) == "table" then return ns end
    local lent = type(ns.ExportPublic) ~= "function"
    if lent then ns.ExportPublic = function(_, value) return value end end
    for _, file in ipairs(Loader.FILES) do
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. file))("MidnightSimpleUnitFrames", ns)
    end
    if lent then ns.ExportPublic = nil end
    assert(type(ns.ProfileNormalize) == "table", "the profile normalizer did not publish MSUF.ProfileNormalize")
    return ns
end

return Loader
