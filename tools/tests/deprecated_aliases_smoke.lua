-- deprecated_aliases_smoke.lua <repoRoot>
--
-- Several functions are published under a second, older global name for
-- external callers (user scripts, other addons). They stay, but are marked as
-- deprecated compatibility aliases: each defining file records them in
-- MSUF.Compat.DeprecatedAliases[alias] = canonical. Pinned here:
--   * every client's real load graph publishes exactly the expected aliases;
--   * an alias is the very same function as its canonical name, so the two
--     can never drift apart;
--   * MSUF code calls the canonical names: an alias is referenced only where
--     it is defined, plus the recorded callers other packages still have to
--     switch (the list only shrinks).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local EXPECTED = {
    MSUF_Core_RunNextFrame = "MSUF_RunNextFrame",
    MSUF_ApplyAllAlpha = "MSUF_RefreshAllUnitAlphas",
    MSUF_ApplyPowerBarBorder_All = "MSUF_ApplyBarOutlineThickness_All",
    MSUF_FontPathMatches = "MSUF_FontPathEquals",
    MSUF_Profiles_ExportExternal = "MSUF_ExportExternal",
    MSUF_Profiles_ImportExternal = "MSUF_ImportExternal",
    MSUF_Profiles_ExportSelectionToString = "MSUF_ExportSelectionToString",
    MSUF_Profiles_ImportFromString = "MSUF_ImportFromString",
    MSUF_Profiles_ImportIntoNewProfile = "MSUF_ImportIntoNewProfile",
    MSUF_RefreshUnitDispelOverlay = "MSUF_RefreshUnitDispelOverlays",
    GetInternalFontPathByKey = "MSUF_GetInternalFontPathByKey",
    UpdateAllBarTextures = "MSUF_UpdateAllBarTextures_Immediate",
}

-- Callers outside the engine and state area that still use an alias name.
-- Owners: Edit Mode (A-C6, the preview wrapper list names both spellings on
-- purpose), Menu2 theme (A-C5). ClassPower calls MSUF_FontPathEquals.
local KNOWN_CALLERS = {
    ["MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Compat.lua"] = {
        MSUF_ApplyPowerBarBorder_All = true, MSUF_ApplyAllAlpha = true },
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"] = { MSUF_FontPathMatches = true },
}

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local registry = world.core.Compat and world.core.Compat.DeprecatedAliases
    Check(type(registry) == "table", flavor .. ": MSUF.Compat.DeprecatedAliases is missing")
    for alias, canonical in pairs(EXPECTED) do
        Check(registry[alias] == canonical, flavor .. ": " .. alias .. " is not recorded as an alias of " .. canonical)
        local value = rawget(world.env, canonical)
        Check(type(value) == "function", flavor .. ": canonical " .. canonical .. " is not published")
        Check(rawget(world.env, alias) == value, flavor .. ": " .. alias .. " drifted away from " .. canonical)
    end
    for alias in pairs(registry) do
        Check(EXPECTED[alias] ~= nil, flavor .. ": unexpected deprecated alias " .. tostring(alias) .. "; list it here")
    end
end

-- Source references to an alias name.
local function ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- MidnightSimpleUnitFrames MidnightSimpleUnitFrames_Options', "r"))
local stale, problems, scanned = {}, {}, 0
for path in pipe:lines() do
    if path:match("%.lua$") then
        local text = ReadFile(root .. "/" .. path)
        if text then
            scanned = scanned + 1
            for alias in pairs(EXPECTED) do
                local defining = text:find('DeprecatedAliases.' .. alias .. ' = "', 1, true) ~= nil
                if not defining then
                    for line in text:gmatch("[^\n]+") do
                        if not line:match("^%s*%-%-")
                            and (line:find("[^%w_]" .. alias .. "[^%w_]") or line:find("^" .. alias .. "[^%w_]")) then
                            local known = KNOWN_CALLERS[path] and KNOWN_CALLERS[path][alias]
                            if known then stale[path .. ":" .. alias] = true
                            else problems[#problems + 1] = path .. " calls the deprecated alias " .. alias
                                .. "; call " .. EXPECTED[alias] .. " instead" end
                            break
                        end
                    end
                end
            end
        end
    end
end
pipe:close()
Check(scanned >= 300, "only " .. scanned .. " Lua files scanned; git ls-files failed?")
for path, aliases in pairs(KNOWN_CALLERS) do
    for alias in pairs(aliases) do
        if not stale[path .. ":" .. alias] then
            problems[#problems + 1] = "known caller " .. path .. " no longer uses " .. alias .. "; drop it from KNOWN_CALLERS"
        end
    end
end
Check(#problems == 0, "deprecated_aliases_smoke:\n  " .. table.concat(problems, "\n  "))
print("deprecated_aliases_smoke: ok (" .. scanned .. " files)")
