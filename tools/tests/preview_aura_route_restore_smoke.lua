-- preview_aura_route_restore_smoke.lua <root> <flavor> [selection]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local tests = arg[0]:gsub("\\", "/"):match("^(.*)/") or "."
local Open = assert(loadfile(tests .. "/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "uf_player", clientScriptBindings = true })
local preview, handles, M = mw.core.UFPreview, mw.core.UFPreviewViewHandles, mw.M
local box = assert(preview.active)
if arg[3] == "selection" then
    local model = mw.core.MSUF_Auras3.MenuModel
    model.SetUnitEnabled("player", true)
    model.SetGroupShown("player", "buff", true)
    model.SetGroupShown("player", "debuff", true)
    preview.Refresh(box, "AURA_ROUTE_TEST")
end
assert(M.unitAuraTabSelection.player == nil or M.unitAuraTabSelection.player == "buff")
assert(handles.OpenPreviewHandleSettings(assert(box.handleAuraBuffs), "click"))
mw:RunTimers()
assert(preview._restoreHandleKey == nil, "same-view route left a stale handle restore request")
M.HideSlashMenuAndMinibar(mw.win)
assert(M.Open("uf_player") ~= false)
mw:RunTimers()
assert(preview._restoreHandleKey == nil, "reopen retained a stale handle restore request")
if arg[3] == "selection" then
    for _, field in ipairs({ "handleAuraDebuffs", "handleAuraBuffs", "handleAuraDebuffs", "handleAuraBuffs" }) do
        local handle = assert(preview.active[field])
        assert(handle:IsShown() and handle._msufPlaced ~= false, "test requires a placed aura handle")
        assert(handles.OpenPreviewHandleSettings(handle, "click"))
        mw:RunTimers()
        assert(preview.active._selectedHandle == preview.active[field], "changed view did not restore its selected aura handle")
        assert(preview._restoreHandleKey == nil, "changed view left its restore request pending")
    end
end
print("preview_aura_route_restore_smoke " .. flavor .. ": same-view queue clear" ..
    (arg[3] == "selection" and "; cached view selection restored" or ""))
