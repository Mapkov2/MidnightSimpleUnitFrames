-- editmode_group_geometry_util_smoke.lua <repoRoot>
--
-- Review R7 P3: the layout drag commit (EditMode_Layout) and the HUD Settings
-- and Reset actions (EditMode_HUD_Selection) carried the same group geometry
-- refresh chain line for line. It lives once now, as
-- EM2.Util.RefreshGroupGeometryScoped(kind, reason) in EditMode_Core. Wave 4
-- dropped the public GF alias steps (MSUF_GF_RefreshGeometry and friends call
-- the same GF methods, which load on every client) and the HUD Reset's own
-- copy, which only ran without MSUF_GF_EM2_ResetPosition:
--   1. no Edit Mode file keeps an alias chain, the layout drag passes its own
--      apply reason, and the HUD Reset goes through the group Edit Mode reset;
--   2. the chain: the menu apply service when it is loaded (one group
--      geometry request, then a flush), else GF.RefreshGeometry, else
--      GF.RefreshVisuals with the dirty mask; no kind or no GF does nothing.
--
-- Boots the real Mainline core and Options graph (tools/tests/client_world.lua).
-- Plain Lua 5.1 with the repo root as argument.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error("editmode_group_geometry_util_smoke: " .. message, 2) end
    return condition
end
local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

---------------------------------------------------------------------------
-- 1. One copy, two callers
---------------------------------------------------------------------------
local EDIT = "MidnightSimpleUnitFrames/Shell/EditMode/"
local CHAIN = "_G.MSUF_GF_RefreshGeometry(kind)\n        if type(_G.MSUF_GF_RefreshUnitBindings) == \"function\" then"
local copies = 0
local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "' .. EDIT .. '*.lua"', "r"))
for path in pipe:lines() do
    local _, count = Read(path):gsub(CHAIN:gsub("%p", "%%%0"), "")
    copies = copies + count
end
pipe:close()
Check(copies == 0, "the group geometry alias chain is back in Edit Mode (" .. copies .. " copies)")
Check(Read(EDIT .. "MSUF_EditMode_Layout.lua"):find('U.RefreshGroupGeometryScoped(kind, "EM2_LAYOUT_GROUP_GEOMETRY")', 1, true),
    "the layout drag commit no longer calls the Util refresh with its reason")
Check(Read(EDIT .. "MSUF_EditMode_HUD_Selection.lua"):find('MSUF.Require("MSUF_GF_EM2_ResetPosition", CALLER)(groupKind)', 1, true),
    "the HUD Reset no longer goes through the group Edit Mode reset")

---------------------------------------------------------------------------
-- 2. The chain
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline"):Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env, core = world.env, world.core
local EM2 = Check(env.MSUF_EM2, "Edit Mode did not load")
local Refresh = Check(EM2.Util and EM2.Util.RefreshGroupGeometryScoped, "EM2.Util.RefreshGroupGeometryScoped is missing")

local calls = {}
local function Log(name) return function(...) calls[#calls + 1] = { name, ... } end end
local function Reset() for i = #calls, 1, -1 do calls[i] = nil end end
local menu = core.MSUF2
local savedApply = menu and menu.ApplyService
local savedApplyGlobal = env.MSUF_Menu2_ApplyService
local savedGF = core.GF
local ALIASES = { "MSUF_GF_RefreshGeometry", "MSUF_GF_RefreshUnitBindings", "MSUF_GF_RefreshVisuals",
    "MSUF_GF_RefreshAll", "MSUF_GF_Refresh" }
local savedAliases = {}
for _, name in ipairs(ALIASES) do savedAliases[name] = env[name] end

-- Options loaded: one request through the apply service.
menu.ApplyService = { RequestGroup = Log("RequestGroup"), Flush = Log("Flush") }
Check(Refresh("raid", "SMOKE_REASON") == true, "the apply-service path did not report success")
Check(#calls == 2 and calls[1][1] == "RequestGroup" and calls[1][2] == "raid" and calls[1][3] == "geometry"
    and calls[1][4] == "SMOKE_REASON" and calls[2][1] == "Flush", "the apply service did not get one geometry request and a flush")
Reset()
Check(Refresh(nil, "SMOKE_REASON") == false and #calls == 0, "no kind still refreshed something")

-- Options not loaded: GF directly.
menu.ApplyService, env.MSUF_Menu2_ApplyService = nil, nil
core.GF = { RefreshGeometry = Log("GF.RefreshGeometry"), RefreshVisuals = Log("GF.RefreshVisuals"), DIRTY_LAYOUT = 4 }
Check(Refresh("party", "SMOKE_REASON") == true and #calls == 1 and calls[1][1] == "GF.RefreshGeometry"
    and calls[1][2] == "party", "without the menu, GF.RefreshGeometry was not the one call")
Reset()

-- Without GF.RefreshGeometry: GF.RefreshVisuals with the dirty mask; the
-- public aliases are never asked.
core.GF = { DIRTY_LAYOUT = 4, RefreshVisuals = Log("GF.RefreshVisuals") }
for _, name in ipairs(ALIASES) do env[name] = Log(name) end
Check(Refresh("party", "SMOKE_REASON") == true and #calls == 1 and calls[1][1] == "GF.RefreshVisuals" and calls[1][3] == 4,
    "without geometry refreshes, GF.RefreshVisuals with the mask was not the one call")
Reset()
core.GF = nil
Check(Refresh("party", "SMOKE_REASON") == false and #calls == 0, "without GF, the refresh reported success or called an alias")

menu.ApplyService, env.MSUF_Menu2_ApplyService, core.GF = savedApply, savedApplyGlobal, savedGF
for _, name in ipairs(ALIASES) do env[name] = savedAliases[name] end
print("editmode_group_geometry_util_smoke: ok (one chain in Util; layout reason; HUD reset via GF; 5 steps)")
