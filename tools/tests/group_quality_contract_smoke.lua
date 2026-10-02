-- group_quality_contract_smoke.lua <repoRoot>
--
-- Quality contracts of the group-owned files (GroupFrames/,
-- UnitFrames/Engine/Group/, Game/Forever/GroupFrames/), wave 2 of the 2026-10
-- quality program:
--   * Require, not guards: no group file guards an MSUF_ export with
--     type(_G.MSUF_X) == "function" (inline or through a local alias checked
--     right below it). A guard cannot tell an optional collaborator from a
--     provider that was renamed or dropped, so the feature behind it silently
--     stops working. On every client the group compiler's required exports
--     (the UF settings cache and the castbar statusbar texture resolver)
--     resolve on the real load graph, and a configured temporary max-health
--     texture key reaches the compiled spec through the resolver.
--   * No dead code: no read of a global nothing defines (the retired
--     temporary-profile flag and the legacy group options panel), and no
--     file-scope alias (`local X = X`, `local X = _G.X`) that nothing reads.
--   * Named constants: the saved grid position modes and Priority anchor
--     modes are spelled once, in GF.GRID_POSITION_MODES and
--     GF.PRIORITY_ANCHOR_MODES (MSUF_GroupFrames_DB.lua); the Priority option
--     setter accepts exactly those anchor modes.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"), "missing " .. relative)
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"))
end

local function ListGroupFiles()
    local files = {}
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- '
        .. '"MidnightSimpleUnitFrames/GroupFrames/*.lua" '
        .. '"MidnightSimpleUnitFrames/UnitFrames/Engine/Group/*.lua" '
        .. '"MidnightSimpleUnitFrames/Game/Forever/GroupFrames/*.lua"'))
    for line in pipe:lines() do files[#files + 1] = line end
    pipe:close()
    Check(#files >= 20, "expected the group-owned Lua files, git ls-files listed " .. #files)
    return files
end

-- Source lines with comments removed; string literals kept, so a mode literal
-- still counts as code.
local function CodeLines(source)
    source = source:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    local lines = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    return lines
end

local GROUP_FILES = ListGroupFiles()
local codeByFile = {}
for _, relative in ipairs(GROUP_FILES) do codeByFile[relative] = CodeLines(Read(relative)) end

---------------------------------------------------------------------------
-- Require, not guards
---------------------------------------------------------------------------
local guards = {}
for _, relative in ipairs(GROUP_FILES) do
    local lines = codeByFile[relative]
    for index, code in ipairs(lines) do
        local name = code:match('type%(%s*_G%.(MSUF_[%w_]+)%s*%)%s*[~=]=%s*"function"')
        if not name then
            local alias, global = code:match("local%s+([%w_]+)%s*=%s*_G%.(MSUF_[%w_]+)%s*$")
            if alias then
                for nextIndex = index + 1, math.min(index + 3, #lines) do
                    if lines[nextIndex]:find("type%(%s*" .. alias .. "%s*%)%s*[~=]=%s*\"function\"") then
                        name = global
                        break
                    end
                end
            end
        end
        if name then guards[#guards + 1] = relative .. ":" .. index .. " guards " .. name end
    end
end
Check(#guards == 0, "group files guard in-addon exports instead of requiring them:\n  "
    .. table.concat(guards, "\n  "))

local config = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
for _, name in ipairs({ "MSUF_UFCore_GetSettingsCache", "MSUF_ResolveStatusbarTextureKey" }) do
    Check(config:find('MSUF.Require("' .. name .. '", CONFIG_FILE)', 1, true),
        "Group_Config no longer requires " .. name)
end

---------------------------------------------------------------------------
-- No dead code
---------------------------------------------------------------------------
local RETIRED_GLOBALS = { "MSUF_ProfileIO_SuppressRuntimeSideEffects", "MSUF_GFOptionsPanel" }
local deadAliases = {}
for _, relative in ipairs(GROUP_FILES) do
    local lines = codeByFile[relative]
    local text = table.concat(lines, "\n")
    for _, name in ipairs(RETIRED_GLOBALS) do
        Check(not text:find(name, 1, true), relative .. " still reads the retired global " .. name)
    end
    for index, code in ipairs(lines) do
        local alias, global = code:match("^local%s+([%w_]+)%s*=%s*_G%.([%w_]+)%s*$")
        if not alias then alias, global = code:match("^local%s+([%w_]+)%s*=%s*([%w_]+)%s*$") end
        if alias and alias == global then
            local uses = 0
            for _ in text:gmatch("%f[%w_]" .. alias .. "%f[^%w_]") do uses = uses + 1 end
            -- the declaration names it twice (`local X = X`) or once (`= _G.X`
            -- is a field, but the frontier still matches the trailing X)
            if uses <= 2 then deadAliases[#deadAliases + 1] = relative .. ":" .. index .. " " .. alias end
        end
    end
end
Check(#deadAliases == 0, "group files keep file-scope aliases nothing reads:\n  " .. table.concat(deadAliases, "\n  "))

---------------------------------------------------------------------------
-- Named constants: grid position modes
---------------------------------------------------------------------------
local MODES_OWNER = "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"
for _, relative in ipairs(GROUP_FILES) do
    if relative ~= MODES_OWNER then
        local text = table.concat(codeByFile[relative], "\n")
        for _, literal in ipairs({ '"GRID_BOUNDS_V2"', '"GRID_CENTER_V1"' }) do
            Check(not text:find(literal, 1, true),
                relative .. " spells the saved mode " .. literal .. " instead of GF.GRID_POSITION_MODES")
        end
        for _, literal in ipairs({ '"RAID_RIGHT"', '"RAID_LEFT"', '"RAID_TOP"', '"RAID_BOTTOM"' }) do
            Check(not text:find(literal, 1, true),
                relative .. " spells the Priority anchor mode " .. literal .. " instead of GF.PRIORITY_ANCHOR_MODES")
        end
    end
end

---------------------------------------------------------------------------
-- Priority Frames hotkey feedback is translated (UIErrors)
---------------------------------------------------------------------------
-- code, name, limit, the English text the hotkey always showed
local FEEDBACK = {
    { "ADDED", "Anna", nil, "Priority Frames: added Anna", "Priority Frames: added %s" },
    { "REMOVED", "Anna", nil, "Priority Frames: removed Anna", "Priority Frames: removed %s" },
    { "AUTO_TANK", "Tom", nil, "Tom is already included automatically as a tank.",
        "%s is already included automatically as a tank." },
    { "ADDED_AUTO_TANK", "Tom", nil, "Priority Frames enabled; Tom is included as a tank.",
        "Priority Frames enabled; %s is included as a tank." },
    { "REMOVED_AUTO_TANK", "Tom", nil, "Manual pin removed; Tom remains as an automatic tank.",
        "Manual pin removed; %s remains as an automatic tank." },
    { "FULL", "Anna", 3, "Priority Frames are full (3).", "Priority Frames are full (%s)." },
    { "FULL", "Anna", nil, "Priority Frames are full (5).", "Priority Frames are full (%s)." },
    { "NOT_IN_GROUP", nil, nil, "Join a party or raid before selecting a Priority Frame.",
        "Join a party or raid before selecting a Priority Frame." },
    { "PIN_LIMIT", "Anna", 5, "The saved Priority Frames list is full.", "The saved Priority Frames list is full." },
}
local HOVER_HINT = "Hover an MSUF Party, Raid, or Priority frame, then press the Priority Frames key."
FEEDBACK[#FEEDBACK + 1] = { "INVALID_UNIT", nil, nil, HOVER_HINT, HOVER_HINT }
FEEDBACK[#FEEDBACK + 1] = { "NOT_PINNED", "Anna", nil, HOVER_HINT, HOVER_HINT }

-- Runs every result code through the real hotkey path and returns the
-- UIErrors lines in FEEDBACK order.
local function CollectFeedback(world)
    local env, GF = world.env, world.core.GF
    local lines = {}
    env.UIErrorsFrame = { AddMessage = function(_, text) lines[#lines + 1] = text end }
    local savedHovered, savedToggle = GF.GetHoveredPriorityUnit, GF.TogglePriorityUnit
    for _, case in ipairs(FEEDBACK) do
        GF.GetHoveredPriorityUnit = function() return "party1" end
        GF.TogglePriorityUnit = function() return false, case[1], case[2], case[3] end
        GF.ToggleHoveredPriorityFrame()
    end
    GF.GetHoveredPriorityUnit, GF.TogglePriorityUnit = savedHovered, savedToggle
    env.UIErrorsFrame = nil
    Check(#lines == #FEEDBACK, "the Priority hotkey showed " .. #lines .. " of " .. #FEEDBACK .. " UIErrors lines")
    return lines
end

do
    local english = CollectFeedback(World.New(root, "Mainline"):Boot())
    for index, case in ipairs(FEEDBACK) do
        Check(english[index] == case[4], "enUS " .. case[1] .. " feedback changed: " .. tostring(english[index]))
    end
    local world = World.New(root, "Mainline", { locale = "deDE" }):Boot()
    world.core.FinalizeLocale()
    Check(world.core.LOCALE == "deDE", "the deDE pack was not selected")
    local german = CollectFeedback(world)
    for index, case in ipairs(FEEDBACK) do
        local translated = rawget(world.core.L, case[5])
        Check(type(translated) == "string" and translated ~= case[5], "deDE does not translate " .. case[5])
        local subject = case[1] == "FULL" and tostring(case[3] or 5) or tostring(case[2])
        Check(german[index] == translated:format(subject),
            "deDE " .. case[1] .. " feedback is not the translated text: " .. tostring(german[index]))
    end
end

---------------------------------------------------------------------------
-- Every client: the required exports resolve on the real load graph
---------------------------------------------------------------------------
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. " did not boot: " .. tostring(failure and failure.file)
        .. " " .. tostring(failure and failure.message))
    local env, GF = world.env, world.core.GF
    Check(GF.GRID_POSITION_MODES.STABLE == "GRID_BOUNDS_V2" and GF.GRID_POSITION_MODES.LEGACY == "GRID_CENTER_V1",
        flavor .. ": the saved grid position mode values changed")
    local anchorModes = GF.PRIORITY_ANCHOR_MODES
    Check(anchorModes.RIGHT == "RAID_RIGHT" and anchorModes.LEFT == "RAID_LEFT" and anchorModes.TOP == "RAID_TOP"
        and anchorModes.BOTTOM == "RAID_BOTTOM" and anchorModes.FREE == "FREE",
        flavor .. ": the saved Priority anchor mode values changed")
    GF.EnsureDB()
    Check(GF.GetPriorityConf().anchorMode == "RAID_RIGHT", flavor .. ": the Priority strip no longer docks right by default")
    for _, mode in pairs(anchorModes) do
        Check(GF.SetPriorityOption("anchorMode", mode) == true, flavor .. ": Priority refused anchor mode " .. mode)
    end
    Check(GF.SetPriorityOption("anchorMode", "RAID_CENTER") == false and GF.SetPriorityOption("anchorMode", nil) == false,
        flavor .. ": Priority accepted an unknown anchor mode")
    GF.SetPriorityOption("anchorMode", anchorModes.RIGHT)
    Check(type(rawget(env, "MSUF_UFCore_GetSettingsCache")) == "function", flavor .. ": settings cache export missing")
    local resolve = rawget(env, "MSUF_ResolveStatusbarTextureKey")
    Check(type(resolve) == "function", flavor .. ": statusbar texture resolver export missing")

    GF.EnsureDB()
    local general = env.MSUF_DB.general
    general.tempMaxHealthTexture = "Flat"
    GF.InvalidateCompiledSpecs()
    local spec = GF.CompileSpec("party")
    Check(type(spec) == "table" and type(spec.health) == "table", flavor .. ": the party spec did not compile")
    Check(spec.tempMaxHealth.texture == resolve("Flat"),
        flavor .. ": the temporary max-health texture key bypassed the resolver: " .. tostring(spec.tempMaxHealth.texture))
    general.tempMaxHealthTexture = nil
    GF.InvalidateCompiledSpecs()
end

print("group_quality_contract_smoke: ok")
