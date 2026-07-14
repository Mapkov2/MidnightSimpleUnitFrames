_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local root = RuntimeManifest.ResolveCompanionRoot() .. "/Assistant/"

local buildCalls = 0
local registerCalls = 0
local settings = {}
local MSUF = {
    MSUF2 = {},
    Assistant = {
        Parser = {
            Trim = function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end,
            Normalize = function(value) return tostring(value or ""):lower() end,
        },
    },
}

MSUF.Assistant.Registry = {
    GetSetting = function(_, key) return settings[key] end,
    RegisterSetting = function(_, spec)
        registerCalls = registerCalls + 1
        settings[spec.key] = spec
        return spec
    end,
}
MSUF.Assistant.CoverageAudit = {
    BuildCoveredSets = function()
        buildCalls = buildCalls + 1
        return { general = {} }
    end,
    IsCoveredKey = function(set, key) return set[key] ~= nil end,
    NormalizeCoverageKey = function(key) return key end,
    IsIgnored = function() return false end,
}
MSUF.Assistant.AutoCoverageManifest = {
    defaults = { general = { lazyCoverageFlag = true } },
}

_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = { general = { lazyCoverageFlag = true } }

local function loadAssistant(name)
    local chunk, err = loadfile(root .. name)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

loadAssistant("MSUF_AssistantRegistry_AutoCoverage.lua")
assert(buildCalls == 0 and registerCalls == 0, "auto-coverage must not run while files load")

loadAssistant("MSUF_AssistantParser.lua")
local parsed = MSUF.Assistant.Parse("")
assert(parsed and parsed.kind == "empty", "minimal assistant parse failed")
assert(buildCalls == 1, "first assistant parse must fill auto-coverage once")
assert(registerCalls == 1, "first assistant parse must register the uncovered scalar")

MSUF.Assistant.Parse("")
assert(buildCalls == 1 and registerCalls == 1, "later parses must not rebuild auto-coverage")

io.write("assistant_autocoverage_lazy_smoke: ok\n")
