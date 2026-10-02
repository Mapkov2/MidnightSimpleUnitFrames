local _, MSUF = ...

-- Explicit validation failures may be reported without raising. Runtime
-- exceptions use the client's normal Lua error path at their original call.
local function ReportError(label, err)
    _G.geterrorhandler()("MSUF " .. tostring(label) .. ": " .. tostring(err))
    return true
end

MSUF.ReportError = ReportError
MSUF.ExportPublic("MSUF_ReportError", ReportError)

-- Native codecs reject malformed payloads by raising. Keep that rejection at
-- the factory-profile input boundary; unrelated runtime errors still propagate.
local function TryDeserializeFactoryPayload(encoding, payload)
    if type(payload) ~= "string" or payload == "" then return nil end
    local ok, value = pcall(encoding.DeserializeCBOR, payload)
    return ok and type(value) == "table" and value or nil
end

local function TryDecodeFactoryPayload(encoding, cleaned)
    if type(encoding) ~= "table" or type(encoding.DecodeBase64) ~= "function"
        or type(encoding.DeserializeCBOR) ~= "function" then return nil end
    local decoded, blob = pcall(encoding.DecodeBase64, cleaned)
    if not decoded or type(blob) ~= "string" or blob == "" then return nil end
    -- Current exports are deflate(CBOR); older exports may contain raw CBOR.
    if type(encoding.DecompressString) == "function" then
        local method = _G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate
        local inflated, payload
        if method ~= nil then
            inflated, payload = pcall(encoding.DecompressString, blob, method)
        else
            inflated, payload = pcall(encoding.DecompressString, blob)
        end
        if inflated then
            local value = TryDeserializeFactoryPayload(encoding, payload)
            if value then return value end
        end
    end
    return TryDeserializeFactoryPayload(encoding, blob)
end

MSUF.TryDecodeFactoryPayload = TryDecodeFactoryPayload
-- Profile import strings reach the same native CBOR rejection: a garbled
-- payload must come back as a failed decode (an import message), never as a
-- Lua error from inside the codec.
MSUF.TryDeserializeNativeCBOR = TryDeserializeFactoryPayload

-- Another addon's step that the host runs inside its own state: Menu2 runs
-- the prepare, reset and finish steps of a host API v1 page-reset provider
-- around its undo history. A step that raises is reported like any other
-- Lua error and the host gets nil back, so its own state (the history depth)
-- always closes again. Every other runtime error keeps the normal path.
local function RunPageResetProviderStep(step, pageKey, label)
    local ok, result = pcall(step, pageKey)
    if ok then return result end
    ReportError("page-reset provider " .. tostring(label) .. " " .. tostring(pageKey), result)
    return nil
end

MSUF.RunPageResetProviderStep = RunPageResetProviderStep
