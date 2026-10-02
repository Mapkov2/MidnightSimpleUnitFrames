-- menu_required_owners_smoke.lua <repoRoot>
--
-- The menu and Edit Mode resolve collaborators the addon itself defines as
-- hard dependencies: MSUF.Require (or a module table) at file load, never a
-- type(...) == "function" guard or an `a or _G.b` fallback chain that turns a
-- renamed or dropped export into silence (review R7 item 4, AGENTS_QUALITY
-- section 3 "Design").
--
--   1. owners that must be resolved through MSUF.Require at load;
--   2. fallback chains that must not come back.
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

if #failures > 0 then
    error("menu_required_owners_smoke: " .. #failures .. " problem(s):\n  " .. table.concat(failures, "\n  "))
end
print(string.format("menu_required_owners_smoke: ok (%d required owners, %d forbidden fallbacks)",
    #REQUIRED, #FORBIDDEN))
