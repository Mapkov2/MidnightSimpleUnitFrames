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
local function Descends(frame, parent)
    while frame do
        if frame == parent then return true end
        frame = frame:GetParent()
    end
end
assert(M.Open("opt_bars"))
Settle()
local choices = {}
for _, frame in ipairs(mw.world.widgets.frames) do
    if frame._msuf2BarPreview and frame.RefreshPreview and Descends(frame, mw.win) then
        choices[#choices + 1] = frame
    end
end
assert(#choices > 0, "Bars did not create an absorb anchor sample")
for _, choice in ipairs(choices) do
    local lane = choice._msuf2BarPreview[1]
    local sample = assert(lane.surface.scene, "absorb anchor scene missing"):Frame()
    assert(sample:GetParent() == lane.host, "absorb sample escaped its dropdown lane")
    assert(not sample._msufGFFrameAuraPreviewHosts and not sample._msufSceneEffectOwner,
        "bar dropdown built aura preview hosts")
    assert(not sample.MSUFPortraitHolder and not sample.nameText and not sample.raidTargetIcon,
        "bar dropdown built a full unit frame")
    assert(not choice._msuf2BarPreview[2], "single-lane field created a second renderer")
    assert(sample:GetHeight() == 8 and sample:GetWidth() == lane.host:GetWidth(),
        "bar dropdown did not fit the runtime bar to its lane")
    assert(sample.MSUFSpec.health.vertical == false and sample.MSUFSpec.prediction.absorbOffsetY == 0,
        "bar dropdown inherited unrelated player geometry")
    local scene, paints = lane.surface.scene, 0
    local refresh = scene.Refresh
    function scene:Refresh()
        paints = paints + 1
        return refresh(self)
    end
    MW.FireVisibilityScripts(lane.host)
    lane.host:Hide()
    lane.host:Show()
    assert(paints == 1 and scene:Frame() == sample, "reopen must paint once and reuse its bar")
end
local shapes = {}
for _, frame in ipairs(mw.world.widgets.frames) do
    if frame._msuf2RoundedPreviewSample and Descends(frame, mw.win) then
        shapes[#shapes + 1] = frame._msuf2RoundedPreviewSample
    end
end
assert(#shapes == 2, "rounded and slanted previews were not built")
local db = M.EnsureDB()
db.player.powerBarDetached = true
db.player.embedPowerBarIntoHealth = false
for _, surface in ipairs(shapes) do
    local sample = assert(surface:Refresh(), "unit shape sample missing")
    assert(sample.MSUFSpec.power.embed and not sample.MSUFSpec.power.detached, "detached power escaped the shape sample")
    assert(not sample._msufGFFrameAuraPreviewHosts, "shape sample built aura hosts")
end
db.general.hpPowerTextSelectedKey = "gf_party"
for _, surface in ipairs(shapes) do
    local sample = assert(surface:Refresh(), "party shape sample missing")
    assert(sample._msufGFKind == "party" and sample.MSUFSpec.power.embed, "shape did not fit the selected party scope")
    assert(not sample._msufGFFrameAuraPreviewHosts, "party shape sample built aura hosts")
end
print("menu_preview_close_smoke: ok " .. flavor)
