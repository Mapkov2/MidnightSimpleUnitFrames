-- Real Focus, Quick and AuraPopup entries must reuse controls and re-read profiles.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, route = arg[2] or "Mainline", arg[3] or "focus"
local Open = assert(loadfile(root .. "/tools/tests/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, core, env = mw.M, mw.core, mw.env
local em = assert(core.PublicGlobals.MSUF_EM2)
local function Settle() mw:RunTimers() M.Theme.StopAllMenuAnimations() end
local function Visit()
    if route == "focus" then
        em.Focus.SetSelection("player", "frame", nil, { menu = false })
        assert(em.Focus.OpenFullSettings("uf_player"))
    elseif route == "quick" then
        core.PublicGlobals.MSUF_EM2_Menu2Style.QuickPopup.OpenPage("uf_player")
    else
        core.ExportPublic("MSUF_EM2_ActiveAuraGroup", "custom1")
        assert(em.AuraPopup.Open("player"))
        assert(env.MSUF_EM2_AuraPopup).unitAurasBtn:Click()
        assert(M.unitAuraTabSelection.player == "custom1", "popup lost selected custom lane")
    end
    Settle()
    assert(M.activeKey == "uf_player", "entry opened wrong page")
end
Visit()
-- Warm the native disabled-reason overlay as well as the page before measuring.
M.EnsureDB().player.enabled = false
M.MarkMenuDataDirty()
Visit()
M.EnsureDB().player.enabled = true
M.MarkMenuDataDirty()
Visit()
local entry, frames = M.cache.uf_player, mw:Frames()
local control
for _, widget in ipairs(entry.searchWidgets) do
    if widget._msuf2RuntimeControlRecord and widget._msuf2RuntimeControlRecord.settingKey == "player.enabled" then
        control = widget
        if widget._msuf2CommandAction and widget.SetChecked then break end
    end
end
assert(control and control._msuf2CommandAction, "real Basics control missing")
for cycle = 1, 4 do
    -- Replace the profile root, as a profile switch does; do not call a menu refresher here.
    local db = M.DeepCopy(M.EnsureDB())
    db.player.enabled = cycle % 2 == 0
    env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile] = db
    env.MSUF_DB = db
    Visit()
    assert(M.cache.uf_player == entry, "Edit Mode entry discarded the warmed page")
    assert(control._msuf2CommandAction.get() == db.player.enabled, "entry getter retained old profile")
    assert(control:GetChecked() == db.player.enabled, "entry displayed old profile value")
end
assert(mw:Frames() == frames, route .. ": warmed shell entry grew " .. (mw:Frames() - frames) .. " frames")
print(string.format("editmode_menu_entry_smoke %s %s: profile replacement x4; %d frames, 0 growth", flavor, route, frames))
