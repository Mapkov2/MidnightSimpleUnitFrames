local _, MSUF = ...

-- Explicit validation failures may be reported without raising. Runtime
-- exceptions use the client's normal Lua error path at their original call.
local function ReportError(label, err)
    _G.geterrorhandler()("MSUF " .. tostring(label) .. ": " .. tostring(err))
    return true
end

MSUF.ReportError = ReportError
MSUF.ExportPublic("MSUF_ReportError", ReportError)
