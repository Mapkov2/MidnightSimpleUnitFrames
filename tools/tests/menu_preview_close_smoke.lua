-- Closing a page releases only its previews; an unchanged idle owner must not
-- rebuild the live Boss/Arena families. Castbar-page cleanup still runs.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, core = mw.M, mw.core
local function Settle() mw:RunTimers(); M.Theme.StopAllMenuAnimations() end
local boss, arena = M.UnitPage.SetBossPagePreviewActive, M.UnitPage.SetArenaPagePreviewActive
local calls = 0
local function Count(event)
    if event == "call" then
        local fn = debug.getinfo(2, "f").func
        if fn == boss or fn == arena then calls = calls + 1 end
    end
end
local function Close()
    calls = 0
    debug.sethook(Count, "c")
    M.HideSlashMenuAndMinibar(mw.win)
    Settle()
    debug.sethook()
    return calls
end
assert(Close() == 0, "idle close redundantly synchronizes Boss/Arena previews: " .. calls)
-- The same idle page can coexist with Edit Mode's independent preview request.
local preview = core.UF.Preview
preview.SetEditMode(true)
preview.SetBoss(true)
assert(M.Open("home")); Settle()
assert(Close() == 0, "idle close rebuilt Edit Mode's family previews")
assert(preview.State.editMode == true and preview.State.boss == true, "close changed Edit Mode ownership")
preview.SetEditMode(nil)
preview.SetBoss(nil)
-- Both settled and still queued family pages release their page ownership.
for _, family in ipairs({ "boss", "arena" }) do
    if core.Client.SupportsUnit(family) then
        assert(M.Open("uf_" .. family)); Settle()
        assert(preview.State[family .. "Page"] == true, family .. " page did not acquire its preview")
        Close()
        assert(preview.State[family .. "Page"] ~= true, family .. " page survived close")
        assert(M.Open("uf_" .. family))
        Close() -- Close before the delayed page preview request gets its turn.
        assert(preview.State[family .. "Page"] ~= true, family .. " delayed preview survived close")
        assert(M.Open("uf_" .. family)); Settle()
        mw.world:EnterCombat(); Settle()
        assert(not mw.win:IsShown(), "combat did not close the menu")
        mw.world:LeaveCombat(); Settle()
        assert(preview.State[family .. "Page"] ~= true, family .. " page reactivated after combat")
    end
end
-- A borrowed castbar preview has to stop even though the window is now hidden.
local apply = core.PublicGlobals.MSUF_ApplyCastbarPagePreviewState
local lastUnit, castCalls
core.ExportPublic("MSUF_ApplyCastbarPagePreviewState", function(unit)
    lastUnit, castCalls = unit, (castCalls or 0) + 1
    return unit
end)
assert(M.Open("opt_castbar")); Settle()
assert(lastUnit == "player", "castbar page did not acquire its preview")
castCalls = 0
Close()
assert(castCalls == 1 and lastUnit == nil, "closing leaked/repeated the castbar preview")
assert(M.Open("opt_castbar")); Settle()
mw.world:EnterCombat(); Settle()
assert(not mw.win:IsShown() and lastUnit == nil, "combat close leaked the castbar preview")
mw.world:LeaveCombat(); Settle()
assert(lastUnit == nil, "castbar preview reactivated after combat")
core.ExportPublic("MSUF_ApplyCastbarPagePreviewState", apply)
print("menu_preview_close_smoke: ok " .. flavor)
