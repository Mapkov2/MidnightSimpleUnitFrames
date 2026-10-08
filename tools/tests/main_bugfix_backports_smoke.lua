local root = assert(arg[1], "repository root required"):gsub("\\", "/")
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end

-- Only the factory codec boundary catches malformed native codec inputs.
local ns = { ExportPublic = function() end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MSUF", ns)
assert(type(ns.TryDecodeFactoryPayload) == "function", "factory codec rejection boundary missing")
local source = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
local body = assert(source:match("(local function MSUF_Defaults_TryDecodeCompactString.-)local function MSUF_Defaults_WipeInPlace"))
local payload = { player = { enabled = true } }
local mode, calls, expectedMethod
local encoding = {
    DecodeBase64 = function()
        calls[#calls + 1] = "base64"
        if mode == "badBase64" then error("bad base64") end
        if mode == "emptyBase64" then return nil end
        return mode == "raw" and "CBOR" or "DEFLATE"
    end,
    DecompressString = function(blob, method)
        assert(method == expectedMethod, "deflate method mismatch")
        calls[#calls + 1] = "deflate"
        if mode == "raw" or mode == "badDeflate" then error("bad deflate") end
        assert(blob == "DEFLATE")
        return "CBOR"
    end,
    DeserializeCBOR = function(blob)
        calls[#calls + 1] = "cbor"
        if mode == "badCBOR" or blob ~= "CBOR" then error("bad cbor") end
        if mode == "scalarCBOR" then return 42 end
        return payload
    end,
}
local env = setmetatable({ MSUF = ns }, { __index = _G })
env._G = setmetatable({ C_EncodingUtil = encoding }, { __index = _G })
local chunk = assert(loadstring(body .. "\nreturn MSUF_Defaults_TryDecodeCompactString"))
setfenv(chunk, env)
local decode = chunk()
local originalEnum = _G.Enum
for _, useEnum in ipairs({ false, true }) do
    expectedMethod = useEnum and 7 or nil
    _G.Enum = useEnum and { CompressionMethod = { Deflate = expectedMethod } } or nil
    for _, value in ipairs({ "compressed", "raw", "badBase64", "emptyBase64", "badDeflate", "badCBOR", "scalarCBOR" }) do
        mode, calls = value, {}
        local result = decode("MSUF3:YQ==")
        assert(result == ((mode == "compressed" or mode == "raw") and payload or nil), mode .. ": decoder result")
        if mode == "compressed" then assert(table.concat(calls, ",") == "base64,deflate,cbor", "inflate before CBOR") end
    end
end
_G.Enum = originalEnum
mode, calls = "compressed", {}
assert(decode("MSUF1:YQ==") == nil and decode("MSUF3:a") == nil and #calls == 0, "invalid envelope reached native codec")
local inflate = encoding.DecompressString
encoding.DecompressString = nil
mode, calls = "raw", {}
assert(decode("MSUF3:YQ==") == payload, "raw payload without decompressor")
encoding.DecompressString = inflate
assert(ns.TryDecodeFactoryPayload({}, "YQ==") == nil, "missing codec APIs")

-- Use the actual client load graph so query normalization, index and routing agree.
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    local M = world.core.MSUF2
    -- Search navigation requires an open menu; keep the real query/index path.
    M.frame = world.env.CreateFrame("Frame", nil, world.env.UIParent)
    M.frame:Show()
    local search = M.Search
    for _, query in ipairs({ "m+", "m +", "M  +", "mythic+", "mythic +", "myhtic+", "myhtic +" }) do
        local normalized = search.Text.NormalizeSearchText(query)
        assert(normalized == "mythic plus", query .. ": lost dungeon shorthand: " .. normalized)
        local results = search._CoreAPI.SearchPages(query .. " frames")
        local found = false
        for _, rec in ipairs(results) do if rec.key == "gf_layout" then found = true; break end end
        assert(found, query .. ": group-frame results missing")
        local route = search._RoutingAPI.SearchRouteForTarget("gf_layout", query .. " frames", "")
        assert(route and route.state and route.state.gfScope == "party", query .. ": routed outside Party scope")
    end
    local raid = search._RoutingAPI.SearchRouteForTarget("gf_layout", "mythic raid frames", "")
    -- Only Mainline has a Mythic Raid scope. Other clients route to Raid and
    -- must persist that supported scope when the search result is applied.
    local raidScope = flavor == "Mainline" and "mythicraid" or "raid"
    assert(raid and raid.state and raid.state.gfScope == raidScope, flavor .. ": Mythic Raid route ignored client support")
    M.SetMenuStateValue("gfScope", "party")
    search._RoutingAPI.ApplySearchRoute("gf_layout", raid)
    assert(M.gfScope == raidScope and M.EnsurePersistentMenuState().gfScope == raidScope,
        flavor .. ": Mythic Raid route did not persist the supported scope")
    assert(search.Text.NormalizeSearchText("m plus") == "m plus", "ordinary words were rewritten")
end
print("PASS main bugfix backports: factory codec rejection, native decode order, dungeon query results and exact group scope")
