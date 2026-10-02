-- classic_aura_module_refs_smoke.lua <repoRoot>
--
-- The Classic aura backend imports its modules; it does not guard them.
-- Game/<Flavor>/Auras.xml loads Buttons, Filters, FrameVisuals, Lanes,
-- UnitFrames, Requests and Preview in that order, and each file imports the
-- earlier ones from A3._ClassicBackend. Six files used to return silently when
-- an earlier module was missing (re-review 2026-10-02), which would leave the
-- aura element half installed with no message; Requests also guarded
-- UF.ApplyElementToFrame and looked frames up through three fallbacks that
-- the unit-frame factory fills from the same registration (RegisterGlobals in
-- UnitFrames/Engine/MSUF_UF_Factory.lua).
--
-- Part 1 loads each file without its predecessor and requires a named error;
-- part 2 fails when a silent guard or a redundant fallback comes back.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local AURAS = root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/"

-- 1. A missing predecessor is an error that names the file it needs.
-- Buttons creates A3._ClassicBackend, so "no backend" means Buttons is missing;
-- the later files also need the module right before them.
local CASES = {
    { file = "Filters", needs = "MSUF_Auras3_Buttons.lua" },
    { file = "FrameVisuals", needs = "MSUF_Auras3_Buttons.lua" },
    { file = "Lanes", needs = "MSUF_Auras3_Buttons.lua" },
    { file = "UnitFrames", needs = "MSUF_Auras3_Lanes.lua" },
    { file = "UnitFrames", backend = { Buttons = {} }, needs = "MSUF_Auras3_Lanes.lua" },
    { file = "Requests", needs = "MSUF_Auras3_UnitFrames.lua" },
    { file = "Requests", backend = { Buttons = {}, Lanes = {} }, needs = "MSUF_Auras3_UnitFrames.lua" },
    { file = "Preview", needs = "MSUF_Auras3_Requests.lua" },
    { file = "Preview", backend = { Buttons = {}, Lanes = {}, Element = {} }, needs = "MSUF_Auras3_Requests.lua" },
}
for _, case in ipairs(CASES) do
    local A3 = { _ClassicBackend = case.backend, _ClassicCompile = {} }
    local namespace = { Client = { IsClassic = true }, MSUF_Auras3 = A3, UF = {} }
    _G.MSUF_NS = namespace
    local chunk = assert(loadfile(AURAS .. "MSUF_Auras3_" .. case.file .. ".lua"))
    local ok, message = pcall(chunk, "MidnightSimpleUnitFrames", namespace)
    assert(not ok, case.file .. ".lua loaded without its predecessor instead of naming it")
    assert(tostring(message):find(case.needs, 1, true),
        case.file .. ".lua failed without naming " .. case.needs .. ": " .. tostring(message))
end

-- 2. No silent module guard or redundant frame fallback in the backend.
local FORBIDDEN = {
    { pattern = "if not Backend", label = "a silent Backend guard (assert the import)" },
    { pattern = "if not %(Backend", label = "a silent Backend guard (assert the import)" },
    { pattern = "if UF%.ApplyElementToFrame then", label = "a guard on UF.ApplyElementToFrame (always loaded first)" },
    { pattern = "UF%.frames and UF%.frames%[", label = "a guard on UF.frames (always a table)" },
    { pattern = "_G%.MSUF_UnitFrames", label = "_G.MSUF_UnitFrames (the same table as UF.frames)" },
    { pattern = '_G%["MSUF_" %.%.', label = "a MSUF_<unit> global lookup (the same frame as UF.frames)" },
    { pattern = "A3%.PlayerDefensiveData and", label = "a guard on A3.PlayerDefensiveData (loaded first)" },
}
local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "MidnightSimpleUnitFrames/Game/Classic/Auras/*.lua"'))
local files, failures = 0, {}
for path in pipe:lines() do
    files = files + 1
    local handle = assert(io.open(root .. "/" .. path, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local lineNumber = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        lineNumber = lineNumber + 1
        local code = line:gsub("%-%-.*$", "")
        for _, rule in ipairs(FORBIDDEN) do
            if code:find(rule.pattern) then failures[#failures + 1] = path .. ":" .. lineNumber .. ": " .. rule.label end
        end
    end
end
pipe:close()
assert(files >= 12, "the Classic aura file list is incomplete (" .. files .. " files)")
if #failures > 0 then error("Classic aura backend guards its own modules:\n  " .. table.concat(failures, "\n  "), 0) end
print(("classic_aura_module_refs_smoke: ok (%d load cases, %d files)"):format(#CASES, files))
