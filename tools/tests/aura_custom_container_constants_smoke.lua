-- aura_custom_container_constants_smoke.lua <repoRoot>
--
-- Custom Aura containers are counted and the fixed preset slot (Defensive
-- Buffs on the player frame, Target DoTs elsewhere) is named in one place:
-- A3.CUSTOM_CONTAINER_COUNT and A3.PRESET_CUSTOM_CONTAINER_INDEX in
-- Auras3/MSUF_Auras3_Core.lua. The runtime, the Classic backend, the menu
-- schema and Edit Mode used to compare against a bare 4 (re-review
-- 2026-10-02). Part 1 checks the values and that the menu schema takes them;
-- part 2 fails on a bare 4 standing for either.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local ADDON = root .. "/MidnightSimpleUnitFrames/"

-- 1. The values, and the menu schema's slot names derive from them.
local namespace = {
    ExportPublic = function(name, value) _G[name] = value; return value end,
    MSUF_CreateCanonicalPlayerDefensiveAuraContainer = function() return {} end,
}
_G.MSUF_NS = namespace
assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_Core.lua"))("MidnightSimpleUnitFrames", namespace)
local A3 = namespace.MSUF_Auras3
assert(A3.CUSTOM_CONTAINER_COUNT == 4 and A3.PRESET_CUSTOM_CONTAINER_INDEX == 4,
    "the Custom Aura container count or the preset slot changed")
A3.CUSTOM_CONTAINER_COUNT, A3.PRESET_CUSTOM_CONTAINER_INDEX = 7, 6
assert(loadfile(ADDON .. "Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua"))("MidnightSimpleUnitFrames", namespace)
local Schema = namespace.Auras3MenuModelFactories.Schema(A3)
assert(Schema.CUSTOM_CONTAINER_MAX == 7 and Schema.TARGET_DOT_CONTAINER_INDEX == 6
    and Schema.PLAYER_DEFENSIVE_CONTAINER_INDEX == 6, "the menu schema does not take the core's container constants")

-- 2. No bare 4 for the count or the preset slot. The two Retail-mirrored
-- sites stay until Retail takes the constants (Retail port).
local BARE = {
    "index [=~]= 4%f[%D]", "customIndex [=~]= 4%f[%D]", "%f[%w]i [=~]= 4%f[%D]",
    "for index = 1, 4 do", "for i = 1, 4 do", "math_min%(4, math_max%(1, tonumber%(customIndex%)",
    "items%[4%]", "and a%[4%]",
}
local ALLOWED = {
    ["MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Containers.lua"] = 1,
    ["MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_GroupConfig.lua"] = 1,
}
-- Loops over the four edges or corners of a frame are not container loops.
local NOT_CONTAINERS = {
    ["MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators_Effects.lua"] = true,
    ["MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Appearance.lua"] = true,
    ["MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_DispelVisuals.lua"] = true,
    ["MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Visuals.lua"] = true,
}
local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- MidnightSimpleUnitFrames/Auras3 "MidnightSimpleUnitFrames/Game/*/Auras/*"'))
local files, failures = 0, {}
for path in pipe:lines() do
    if path:match("%.lua$") and not path:find("AliasData", 1, true) and not NOT_CONTAINERS[path] then
        files = files + 1
        local handle = assert(io.open(root .. "/" .. path, "rb"))
        local source = handle:read("*a"):gsub("\r\n", "\n")
        handle:close()
        local hits, lineNumber = 0, 0
        for line in (source .. "\n"):gmatch("([^\n]*)\n") do
            lineNumber = lineNumber + 1
            local code = line:gsub("%-%-.*$", "")
            for _, pattern in ipairs(BARE) do
                if code:find(pattern) then
                    hits = hits + 1
                    if hits > (ALLOWED[path] or 0) then failures[#failures + 1] = path .. ":" .. lineNumber end
                end
            end
        end
        assert(hits >= (ALLOWED[path] or 0), path .. ": its allowlist entry is stale; remove it")
    end
end
pipe:close()
assert(files > 60, "the aura file list is incomplete (" .. files .. " files)")
if #failures > 0 then
    error("a bare 4 stands for the Custom Aura container count or preset slot:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("aura_custom_container_constants_smoke: ok (%d files)"):format(files))
