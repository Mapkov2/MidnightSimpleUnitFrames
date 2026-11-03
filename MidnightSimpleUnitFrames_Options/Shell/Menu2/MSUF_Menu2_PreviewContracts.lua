-- Load-time contracts for the preview's composed owners.
local _, MSUF = ...
local Contracts = {}
MSUF.MSUF2.PreviewContracts = Contracts
function Contracts.RequireFields(domain, values, fields)
    assert(type(values) == "table", domain .. " interface is required")
    for key in fields:gmatch("%S+") do
        assert(values[key] ~= nil, domain .. "." .. key .. " is required")
    end
    return values
end
