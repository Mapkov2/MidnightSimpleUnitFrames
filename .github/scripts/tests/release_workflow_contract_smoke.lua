local ROOT = arg and arg[1] or "."

local function Read(path)
    path = ROOT .. "/" .. path
    local handle = assert(io.open(path, "rb"), "cannot open " .. path)
    local source = handle:read("*a")
    handle:close()
    return (source:gsub("\r\n", "\n"))
end

local function InterfaceSet(path)
    local source = Read(path)
    local value = assert(source:match("^## Interface:%s*([^\n]+)"),
        "Interface metadata missing from " .. path)
    local out = {}
    for token in value:gmatch("%d+") do out[token] = true end
    return out
end

local coreInterfaces = InterfaceSet("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc")
local assistantInterfaces = InterfaceSet("MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc")
for token in pairs(coreInterfaces) do
    assert(assistantInterfaces[token], "Assistant TOC is missing Core interface " .. token)
end
for token in pairs(assistantInterfaces) do
    assert(coreInterfaces[token], "Assistant TOC has an interface absent from Core: " .. token)
end
assert(coreInterfaces["120007"] and coreInterfaces["120100"],
    "release TOCs must support both 12.0.7 and 12.1.0")

local workflow = Read(".github/workflows/release.yml")
local function Position(needle)
    return assert(workflow:find(needle, 1, true), "release workflow is missing: " .. needle)
end

local checkout = Position("      - uses: actions/checkout@v5")
local setupPython = Position("      - uses: actions/setup-python@v6")
local installLua = Position("      - name: Install Lua verification runtime")
local luaAlias = Position('ln -sf "$(command -v lua5.1)" "$RUNNER_TEMP/msuf-assistant-gate-bin/lua"')
local luacAlias = Position('ln -sf "$(command -v luac5.1)" "$RUNNER_TEMP/msuf-assistant-gate-bin/luac"')
local coreSmokes = Position("      - name: Run core Lua 5.1 smokes")
local searchIndex = Position("      - name: Verify generated Menu2 search index")
local searchIndexCheck = Position("run: ./tools/generate_search_static_index.ps1 -Check")
local resolvePublishTarget = Position("      - name: Resolve publish target")
local validatePublishingConfig = Position("      - name: Validate publishing config")
local resolveReleaseChannel = Position("      - name: Resolve release channel")
local enforcePrereleaseChannel = Position("      - name: Enforce prerelease channels for prerelease tags")
local assistantGate = Position("      - name: Run authoritative Assistant release gate")
local gateCommand = Position("run: ./.github/scripts/run_assistant_release_gate.ps1")
local build = Position("      - name: Build AddOns zip")
local githubUpload = Position("      - name: Upload to GitHub Release")
local wagoUpload = Position("      - name: Upload to Wago")
local curseForgeUpload = Position("      - name: Upload to CurseForge")

assert(checkout < setupPython and setupPython < installLua and installLua < coreSmokes
    and coreSmokes < searchIndex and searchIndex < searchIndexCheck,
    "Assistant gate does not run after checkout and required Python/Lua setup")
assert(installLua < luaAlias and luaAlias < assistantGate
    and installLua < luacAlias and luacAlias < assistantGate,
    "Assistant gate does not receive deterministic Lua 5.1 interpreter/compiler aliases")
assert(assistantGate < gateCommand and gateCommand < build,
    "authoritative Assistant gate is not a pre-build hard gate")
assert(searchIndexCheck < resolvePublishTarget
    and resolvePublishTarget < validatePublishingConfig
    and validatePublishingConfig < resolveReleaseChannel
    and resolveReleaseChannel < enforcePrereleaseChannel
    and enforcePrereleaseChannel < assistantGate,
    "expensive Assistant gate must run after all cheap release fail-fast checks")
assert(assistantGate < githubUpload and assistantGate < wagoUpload and assistantGate < curseForgeUpload,
    "a publish path can run before the authoritative Assistant gate")

local releaseGate = Read(".github/scripts/run_assistant_release_gate.ps1")
local schemaGenerator = Read("tools/generate_assistant_control_schema.ps1")
local sourceSnapshot = Read("tools/assistant_graphify_source_snapshot.ps1")
for label, source in pairs({
    ["release gate"] = releaseGate,
    ["schema generator"] = schemaGenerator,
}) do
    assert(source:find("[System.Environment]::OSVersion.Platform", 1, true),
        label .. " does not select a platform-safe mutex name")
    assert(source:find('"MSUF_AssistantSchemaAndReleaseGate_v1"', 1, true),
        label .. " is missing the Unix-safe mutex name")
end
assert(sourceSnapshot:find('manifestFormat = "msuf-addon-source-sha256-v2"', 1, true)
    and sourceSnapshot:find("Get-NormalizedTextFileSha256", 1, true)
    and sourceSnapshot:find("$normalized.WriteByte(10)", 1, true)
    and sourceSnapshot:find("ls-files --cached --others --exclude-standard", 1, true),
    "Graphify source snapshot is not checkout-newline neutral and Git-closure scoped")

print("PASS release workflow contract: TOC parity and Assistant hard gate before every publish path")
