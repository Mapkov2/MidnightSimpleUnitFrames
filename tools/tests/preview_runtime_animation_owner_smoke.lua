-- preview_runtime_animation_owner_smoke.lua <root> <client>
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local namespaced = {
    MSUF_Menu2_UnitPreview_Model = true, MSUF_Menu2_UnitPreview_Specs = true, MSUF_Menu2_UnitPreview_Castbar = true,
    MSUF_Menu2_UnitPreview_Runtime = true, MSUF_Menu2_UnitPreview_ZoomPan = true,
    MSUF_Menu2_UnitPreview_Render = true, MSUF_Menu2_UnitPreview_View_Handles = true,
    MSUF_Menu2_UnitPreview_View_Chrome = true, MSUF_Menu2_UnitPreview_View = true,
}
local legacyCalls = 0
local legacyNames = { "MSUF_BuildPreviewAnimationFrameState", "MSUF_GetPreviewAnimationFrameState",
    "MSUF_BuildPreviewAnimationAuraState", "MSUF_GetPreviewAnimationAuraState" }
local function LegacyCall()
    legacyCalls = legacyCalls + 1
    error("preview called a legacy animation export")
end
local mw = MW.Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local target = path:match("([^/\\]+)$")
        if target ~= "MSUF_Auras3_MockAuraPainter.lua" and target ~= "MSUF_UF_Group_Preview_Samples.lua" then
            return load(self, path, addon, ns)
        end
        local originals = {}
        for _, name in ipairs(legacyNames) do
            originals[name] = self.core.Require(name, "animation ownership test")
            self.core.ExportPublic(name, LegacyCall)
        end
        local ok, result = load(self, path, addon, ns)
        for name, fn in pairs(originals) do self.core.ExportPublic(name, fn) end
        return ok, result
    end
end, beforeOptions = function(world)
    -- Core has finished loading, so its namespace is ready. Consumers must not
    -- route internal animation work through the compatibility exports.
    for _, name in ipairs(legacyNames) do world.core.ExportPublic(name, LegacyCall) end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local name = path:match("([^/\\]+)%.lua$")
        if not namespaced[name] then return load(self, path, addon, ns) end
        local global = self.env.MSUF
        self.env.MSUF = nil
        local ok, result = pcall(load, self, path, addon, ns)
        self.env.MSUF = global
        assert(ok, result)
        return result
    end
end })
local preview = assert(mw.core.UFPreview)
local unit = assert(preview.active)
unit._animationEnabled, unit._animationElapsed = true, .4
preview.Refresh(unit, "namespace-animation")
assert(unit._msufPreviewScene.complete, "unit scene did not complete")
assert(preview.RefreshAnimation(unit), "unit animation did not run")
local unitClock = unit._unitSceneRoot.elapsed
local GF = mw.core.GF
GF.GetConf("party").enabled = true
local group = mw.M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = "gf_layout" })
group:Show()
group._stage:SetSize(600, 220)
group._animationEnabled, group._animationElapsed = true, .8
group:Refresh("namespace-animation")
assert(group:RefreshAnimation(), "group animation did not run")
assert(unit._unitSceneRoot.elapsed == unitClock, "group animation changed the unit clock")
group._animationElapsed = 1.1
assert(group:RefreshAnimation(), "retained group animation did not run")
assert(unit._unitSceneRoot.elapsed == unitClock, "retained group animation changed the unit clock")
group:Hide()
local animation = mw.core.PreviewAnimation
local enabled, elapsed = animation.enabled, animation.Elapsed
animation.enabled = true
animation.Elapsed = function() return .65 end
local editing = mw.env.MSUF_UnitEditModeActive
mw.env.MSUF_UnitEditModeActive = true
GF.SetPreviewAnchor("party", mw.env.UIParent)
GF.ShowPreview("party", 1, { immediate = true })
assert(GF._previewActive.party, "default group preview did not activate")
GF.RefreshPreviewAnimation()
GF.HidePreview("party")
mw.env.MSUF_UnitEditModeActive = editing
local painter = mw.core.MSUF_Auras3.MockAuraPainter
if painter then
    local icon = {}
    assert(painter.AuraState(icon, "buff", 1, {}, nil), "static aura sample failed")
    assert(painter.AuraState(icon, "buff", 1, {}, .5), "animated aura sample failed")
end
animation.enabled, animation.Elapsed = enabled, elapsed
mw.M.HideSlashMenuAndMinibar(mw.win)
assert(mw.M.Open("uf_player") ~= false)
mw:RunTimers()
assert(preview.active._msufPreviewScene.complete, "unit scene did not resume")
assert(legacyCalls == 0, "runtime preview still depends on compatibility animation exports")
print("PASS preview runtime animation owner " .. flavor .. ": namespace, clocks, hide and reopen")
