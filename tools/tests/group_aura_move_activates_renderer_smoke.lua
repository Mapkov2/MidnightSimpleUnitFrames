-- A Group Aura lane only renders in the CUSTOM renderer. Moving a lane in the
-- preview (arrow-key nudge) must leave the renderer active.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env = mw.M, mw.env
M.SetMenuStateValue("gfScope", "party")
mw:Select("gf_auras")
local db = env.MSUF_DB
env.GetCurrentKeyBoardFocus = function() return nil end -- the client world stub reports a focused edit box
local box
for _, candidate in ipairs(M._gfNativePreviews or {}) do
    if candidate:IsShown() then box = candidate end
end
assert(box and box._handleList, "group preview with handles missing")
for _, lane in ipairs({ "buff", "debuff" }) do
    local handle
    for _, candidate in ipairs(box._handleList) do
        if candidate._cfgGroup == lane and not candidate._cfgTrackedBuff then handle = candidate end
    end
    assert(handle and not handle._locked, lane .. ": movable lane handle missing")
    db.gf_party.auras = db.gf_party.auras or {}
    db.gf_party.auras.renderer = "NATIVE_12_1"
    local before = tonumber((db.gf_party.auras[lane] or {}).x) or 0
    box._selectedHandle = handle
    box:GetScript("OnKeyDown")(box, "RIGHT")
    local moved = tonumber((db.gf_party.auras[lane] or {}).x) or 0
    assert(moved ~= before, lane .. ": the nudge did not move the lane")
    assert(db.gf_party.auras.renderer == "CUSTOM", lane .. ": a lane move left the aura renderer inactive")
end
print("group_aura_move_activates_renderer_smoke: PASS (" .. flavor .. ")")
