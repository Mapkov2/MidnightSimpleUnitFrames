-- menu_required_owners_smoke.lua <repoRoot>
--
-- The menu and Edit Mode resolve collaborators the addon itself defines as
-- hard dependencies: MSUF.Require (or a module table) at file load, never a
-- type(...) == "function" guard or an `a or _G.b` fallback chain that turns a
-- renamed or dropped export into silence (review R7 item 4, AGENTS_QUALITY
-- section 3 "Design").
--
--   1. owners that must be resolved through MSUF.Require at load;
--   2. fallback chains that must not come back;
--   3. no type() guards on MSUF_ globals in the pages and Edit Mode;
--   4. every required function exists after a client loads;
--   5. a client without a capability (MSUF.Client.SupportsBlizzardEditMode
--      off: no Enum.EditModeSystem) still loads the Options addon, builds
--      every page, never requires the gated adapter and keeps its switch
--      (disabled).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Fail(message) failures[#failures + 1] = message end

local cache = {}
local function Read(path)
    if cache[path] then return cache[path] end
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    cache[path] = text
    return text
end

local PAGES = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"

---------------------------------------------------------------------------
-- 1. Owners resolved through MSUF.Require at file load
---------------------------------------------------------------------------
local REQUIRED = {
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", "MSUF_GF_AuraFilter",
      "the group aura filter tables (Auras3/MenuModel/MSUF_Auras3_Menu_GroupFilters.lua)" },
}
for _, entry in ipairs(REQUIRED) do
    local path, name, what = entry[1], entry[2], entry[3]
    local text = Read(path)
    local line = text:match("\n(local [%w_]+ = MSUF%.Require%(\"" .. name .. "\"[^\n]*)")
    if not line then
        Fail(path .. " no longer resolves " .. name .. " (" .. what .. ") with MSUF.Require at file load")
    end
end

---------------------------------------------------------------------------
-- 2. Fallback chains that must not come back
---------------------------------------------------------------------------
local FORBIDDEN = {
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", "_G.MSUF_GF_AuraFilter", "group aura filter global fallback" },
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", "GF.AuraFilter", "MSUF.GF.AuraFilter, a field nothing assigns" },
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", "gf.AuraFilter", "MSUF.GF.AuraFilter, a field nothing assigns" },
}
for _, rule in ipairs(FORBIDDEN) do
    local path, needle, label = rule[1], rule[2], rule[3]
    if Read(path):find(needle, 1, true) then Fail(path .. ": " .. label .. " is back (" .. needle .. ")") end
end

---------------------------------------------------------------------------
-- 3. No type(...) == "function" guard on an MSUF_ global in the menu pages
--    or Edit Mode (wave 4 took them from 89 and 94 sites to 1 and 0; the one
--    left is MSUF_Menu2_AuraSettings.lua, a byte-identical Retail mirror whose
--    dead MSUF_IsConfigCombatLocked fallback goes with a Retail port)
---------------------------------------------------------------------------
local GUARD_AREAS = {
    { dir = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/", ceiling = 1 },
    { dir = "MidnightSimpleUnitFrames/Shell/EditMode/", ceiling = 0 },
}
local function TrackedLua(dir)
    local files = {}
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "' .. dir .. '*.lua"', "r"))
    for path in pipe:lines() do files[#files + 1] = path end
    pipe:close()
    return files
end
local guardSites = 0
for _, area in ipairs(GUARD_AREAS) do
    local count, first = 0, nil
    for _, path in ipairs(TrackedLua(area.dir)) do
        local lineNo = 0
        for line in (Read(path) .. "\n"):gmatch("([^\n]*)\n") do
            lineNo = lineNo + 1
            if not line:match("^%s*%-%-") then
                for expr in line:gmatch("type%(%s*([%w_%.%[%]\"]+)%s*%)%s*[~=]=%s*[\"']function[\"']") do
                    local name = expr:gsub("^_G%.", ""):gsub("^_G%[\"", ""):gsub("\"%]$", "")
                    if name:match("^MSUF_[%w_]+$") then
                        count = count + 1
                        first = first or (path .. ":" .. lineNo .. " " .. name)
                    end
                end
            end
        end
    end
    guardSites = guardSites + count
    if count > area.ceiling then
        Fail(string.format("%s guards %d MSUF_ global(s) with type(...) == \"function\" (ceiling %d), first %s",
            area.dir, count, area.ceiling, tostring(first)))
    end
end

---------------------------------------------------------------------------
-- 4. Every function the pages and Edit Mode require exists once a client's
--    core and Options addon have loaded
---------------------------------------------------------------------------
-- Required only inside a Mainline-family block (Midnight, WoW Forever).
local MAINLINE_ONLY = {
    MSUF_ApplyTooltipSpellIDs = true, MSUF_ApplyTooltipCasterNames = true,
    MSUF_EllesmereEditMode_SetEnabled = true,
}
-- Required only while a client capability is on; the provider file returns
-- before exporting anything without it.
local CAPABILITY_GATED = {
    MSUF_BlizzardEditMode_SetEnabled = "SupportsBlizzardEditMode", -- Shell/EditMode/MSUF_EditMode_Blizzard.lua
}
-- Takes Enum.EditModeSystem away before anything loads, so Game/Shared/
-- Initialize.lua reports SupportsBlizzardEditMode off; every other Enum
-- member stays the harness stub.
local function WithoutEditModeSystem(world)
    local stub = world.env.MSUF_REQUIRED_OWNERS_UNMODELLED
    world.env.Enum = setmetatable({}, { __index = function(_, key)
        if key == "EditModeSystem" then return nil end
        return stub
    end })
end
local required = {}
local function Note(name, path)
    if not required[name] then required[name] = path end
end
for _, path in ipairs(TrackedLua("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/")) do
    local text = Read(path)
    for list in text:gmatch("M%.RequireGlobals%(%s*\"[^\"]+\"%s*,%s*(%b{})") do
        for name in list:gmatch("\"(MSUF_[%w_]+)\"") do Note(name, path) end
    end
    for name in text:gmatch("MSUF%.Require%(%s*\"(MSUF_[%w_]+)\"") do Note(name, path) end
end
for _, path in ipairs(TrackedLua("MidnightSimpleUnitFrames/Shell/EditMode/")) do
    for name in Read(path):gmatch("MSUF%.Require%(%s*\"(MSUF_[%w_]+)\"%s*,%s*CALLER%s*%)") do Note(name, path) end
end
local names = {}
for name in pairs(required) do names[#names + 1] = name end
table.sort(names)
if #names < 60 then Fail("only " .. #names .. " required names found; the scan patterns no longer match") end
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local flavors = 0
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    for _, capabilitiesOff in ipairs({ false, true }) do
        local world = World.New(root, flavor)
        if capabilitiesOff then WithoutEditModeSystem(world) end
        world:Boot()
        local label = flavor .. (capabilitiesOff and " without Enum.EditModeSystem" or "")
        local failure = world:FirstFailure()
        if failure then
            Fail(label .. ": boot failed in " .. tostring(failure.file) .. ": " .. tostring(failure.message))
        else
            local classic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists"
            for _, name in ipairs(names) do
                local kind = type(rawget(world.env, name))
                local excused = (classic and MAINLINE_ONLY[name]) or (capabilitiesOff and CAPABILITY_GATED[name])
                if not excused and kind ~= "function" and kind ~= "table" then
                    Fail(label .. ": " .. name .. " (required by " .. required[name] .. ") does not exist after load")
                end
            end
            if capabilitiesOff and world.core.Client.SupportsBlizzardEditMode ~= false then
                Fail(label .. ": SupportsBlizzardEditMode is still on; the capability-off boot proves nothing")
            end
            flavors = flavors + 1
        end
    end
end

---------------------------------------------------------------------------
-- 5. Every page builds with the Blizzard Edit Mode capability off, and the
--    Blizzard frames switch stays on the Misc page, disabled
---------------------------------------------------------------------------
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local builtPages = 0
for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    local mw = MenuWorld.Open(root, flavor, { beforeCore = WithoutEditModeSystem })
    local M, widgets = mw.M, mw.world.widgets
    local keys = {}
    for key in pairs(M.pages) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        M.SelectPage(key)
        widgets:RunTimers()
        local entry = M.cache and M.cache[key]
        if not entry or entry._msuf2BuildIncomplete then
            Fail(flavor .. " without Enum.EditModeSystem: page " .. key .. " did not build")
        else
            builtPages = builtPages + 1
        end
    end
    local switch
    for _, frame in ipairs(widgets.frames) do
        local command = rawget(frame, "_msuf2CommandAction")
        if command and tostring(command.controlId):find("blizzard.edit.mode.integration", 1, true) then switch = frame end
    end
    if not switch then
        Fail(flavor .. " without Enum.EditModeSystem: the Misc page lost its Blizzard frames switch")
    elseif rawget(switch, "_msuf2DesiredEnabled") ~= false then
        Fail(flavor .. " without Enum.EditModeSystem: the Blizzard frames switch is enabled with nothing behind it")
    end
end

if #failures > 0 then
    error("menu_required_owners_smoke: " .. #failures .. " problem(s):\n  " .. table.concat(failures, "\n  "))
end
print(string.format("menu_required_owners_smoke: ok (%d required owners, %d forbidden fallbacks, %d guards,"
    .. " %d required functions on %d boots, %d pages built without Enum.EditModeSystem)",
    #REQUIRED, #FORBIDDEN, guardSites, #names, flavors, builtPages))
