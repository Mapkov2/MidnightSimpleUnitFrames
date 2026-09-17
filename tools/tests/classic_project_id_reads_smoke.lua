-- Raw WOW_PROJECT_ID reads belong in Game/Shared/Initialize.lua, which turns them
-- into MSUF.Client facts. Classic-owned and reviewed override files may keep only
-- the reads listed in ALLOWED, each with the reason it is still raw. Byte-identical
-- Retail copies are Retail's to change until the single-repo cutover, so they are
-- not checked here and a Retail sync never fails on them. Plain Lua 5.1; arg[1]
-- is the repo root.
local repo = assert(arg[1], "repo root required")

local function ReadText(relative)
    local handle = assert(io.open(repo .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local reviewed = {}
for line in ReadText("tools/classic-owned-addon-paths.txt"):gmatch("[^\n]+") do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" then reviewed[path] = "owned" end
end
for line in ReadText("tools/classic-retail-overrides.tsv"):gmatch("[^\n]+") do
    local path = line:match("^([^\t]+)\t")
    if path then reviewed[path] = "override" end
end

local SOURCE_OF_TRUTH = "MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"
-- path = { reads, reason }
local ALLOWED = {
    ["MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"] =
        { 1, "native aura runtime errors are only reported on the Mainline project (Retail code)" },
    ["MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua"] =
        { 1, "cooldown manager project fallback when the file loads without MSUF.Client" },
    ["MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"] =
        { 1, "legacy portrait fallback when the element loads without MSUF.Client" },
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua"] =
        { 2, "Mainline-only option gate kept from the Retail page" },
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"] =
        { 2, "reduced Classic filter fallback when the page loads without MSUF.Client" },
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Classic.lua"] =
        { 2, "reduced Classic filter fallback when the page loads without MSUF.Client" },
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render_Classic.lua"] =
        { 1, "legacy portrait fallback when the preview loads without MSUF.Client" },
}

local command = 'git -C "' .. repo .. '" ls-files -- MidnightSimpleUnitFrames MidnightSimpleUnitFrames_Options'
local pipe = assert(io.popen(command, "r"), "cannot enumerate tracked addon files")
local scanned, failures, seen = 0, {}, {}
for path in pipe:lines() do
    if path:match("%.lua$") and reviewed[path] and path ~= SOURCE_OF_TRUTH then
        scanned = scanned + 1
        local _, reads = ReadText(path):gsub("WOW_PROJECT_ID", "")
        local allowed = ALLOWED[path]
        if reads > 0 or allowed then
            seen[path] = true
            local expected = allowed and allowed[1] or 0
            if reads ~= expected then
                failures[#failures + 1] = string.format(
                    "%s (%s) reads WOW_PROJECT_ID %d times, allowed %d. Route client checks through MSUF.Client (%s), or update ALLOWED with the reason.",
                    path, reviewed[path], reads, expected, SOURCE_OF_TRUTH)
            end
        end
    end
end
local pipeOk, pipeReason, pipeCode = pipe:close()
assert(pipeOk or pipeCode == 0, "git ls-files failed: " .. tostring(pipeReason or pipeCode))
assert(scanned >= 100, "only " .. scanned .. " owned or override Lua files were scanned; git ls-files likely failed")
for path in pairs(ALLOWED) do
    assert(reviewed[path], "ALLOWED names a file that is neither owned nor overridden: " .. path)
    assert(seen[path], "ALLOWED names a file that git does not track: " .. path)
end
assert(#failures == 0, table.concat(failures, "\n"))
print("classic project ID reads smoke passed: " .. scanned .. " owned or override Lua files")
