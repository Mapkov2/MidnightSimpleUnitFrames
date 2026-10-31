-- Nested preview paints must keep each scene's input and the default
-- scene policy. The real group stack and native-shape widgets are loaded.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", arg[3] or "nested"
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, flavor, { beforeBoot = function(world) world.env.MAX_BOSS_FRAMES = 5 end })
local GF = h.GF
local env = assert(loadfile(root .. "/tools/tests/namespace_view.lua"))()(h.world)
local core = h.core
GF.EnsureDB()
core.ExportPublic("MSUF2_GFPagePreviewActive", true)
local conf = GF.GetConf("party")
conf.enabled, conf.levelText, conf.roleIcon = true, true, true
GF.InvalidateCompiledSpecs("party")
local function New(name, class, clock)
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(500, 300)
    local owner = GF.NewPreviewScene(parent)
    local group = owner:Group("party", 2)
    group:Configure({ sample = { name = name, class = class, hpPct = 0.25,
        statusRegions = { { field = "levelText", shown = true, text = name .. " level" } } } })
    owner:Activate()
    h:RunTimers()
    if clock then owner:SetClock(clock, true) end
    return owner, group
end
local outerRoot, outer = New("Outer", "MAGE", 0.2)
local innerRoot, inner = New("Inner", "WARLOCK", 0.8)
local outerFrames, innerFrames = outer:Frames(), inner:Frames()
assert(#outerFrames == 2 and #innerFrames == 2, "scene fixture did not build its rows")
assert(outerFrames[2]._msufGFPreviewClass == "MAGE", "uninterrupted scene sample did not apply")

local observed, sample = {}, core.Require("MSUF_BuildPreviewAnimationFrameState", "preview context test")
core.ExportPublic("MSUF_BuildPreviewAnimationFrameState", function(frame, index, kind, state, elapsed)
    observed[frame] = elapsed
    return sample(frame, index, kind, state, elapsed)
end)
local first = outerFrames[1].hpBar or outerFrames[1].Health or outerFrames[1].health
local setValue, entered = first.SetValue, false
first.SetValue = function(self, ...)
    if not entered then
        entered = true
        if mode == "default" then
            assert(GF.ShowPreview("party", 1, { immediate = true }))
        elseif mode == "error" then
            local bar = innerFrames[1].hpBar or innerFrames[1].Health or innerFrames[1].health
            local before = bar.SetValue
            bar.SetValue = function() error("inner preview sink failure") end
            local ok, why = pcall(inner.RefreshData, inner)
            bar.SetValue = before
            assert(not ok and tostring(why):find("inner preview sink failure", 1, true), "inner error control did not run")
        else
            assert(inner:RefreshData())
        end
    end
    return setValue(self, ...)
end
observed = {}
assert(outer:RefreshData())
first.SetValue = setValue
assert(entered, "nested scene hook did not run")
if mode == "default" then
    local frame = assert(GF._previewFrames.party[1])
    assert(frame._msufGFPreviewClass == "WARRIOR", "default preview inherited an isolated scene sample")
    assert(frame._msufPreviewScene == nil and frame._msufPreviewScope ~= true,
        "default frame changed its legacy isolated-scene marker")
    GF.HidePreview("party")
else
    assert(outerFrames[1].levelText:GetText() == "Outer level", "nested paint replaced the outer scene status sample")
    assert(outerFrames[2]._msufGFPreviewClass == "MAGE", "nested paint replaced the outer scene identity")
    assert(observed[outerFrames[2]] == 0.2, "nested paint replaced the outer scene clock")
    assert(innerFrames[2]._msufGFPreviewClass == "WARLOCK", "outer paint replaced the inner scene identity")
end
-- Interleave direct paints again; an inner error must leave no ambient state.
assert(inner:RefreshData() and outer:RefreshData())
assert(outerFrames[2]._msufGFPreviewClass == "MAGE" and innerFrames[2]._msufGFPreviewClass == "WARLOCK",
    "interleaved paint retained another scene's identity")
-- A pooled frame drops only its own scene; the neighboring scene remains bound.
local held = outerFrames[1]
assert(held._msufGFPreviewScene == outer and innerFrames[1]._msufGFPreviewScene == inner,
    "each shown frame must name its group-scene owner")
outer:SetLayerFilter({ status = false }, nil)
assert(not held.levelText:IsShown() and innerFrames[1].levelText:GetText() == "Inner level",
    "an isolated layer filter escaped to another scene")
outer:Hide()
assert(held._msufGFPreviewScene == nil and not held:IsShown(), "released frame retained its paint owner")
assert(innerFrames[1]._msufGFPreviewScene == inner and innerFrames[1]:IsShown(), "release changed another pool")
outer:Configure({ sample = { name = "Reused", class = "DRUID", hpPct = 0.37,
    statusRegions = { { field = "levelText", shown = true, text = "Reused level" } } }, layerVisible = {} })
assert(outer:Show(1, { immediate = true }))
assert(outer:Frames()[1] == held and held._msufGFPreviewScene == outer,
    "a warm pool did not restore the exact frame owner")
assert(held._msufPreviewScene == outer and held._msufPreviewScope == true and held._msufGFPreviewClass == "DRUID",
    "reuse lost isolated identity or inherited the old sample")
assert(GF.ShowPreview("party", 1, { immediate = true }))
local default = GF._previewFrames.party[1]
assert(default._msufGFPreviewScene ~= outer and default._msufGFPreviewScene.default == true,
    "the default pool borrowed an isolated owner")
assert(default._msufPreviewScene == nil and default._msufPreviewScope ~= true,
    "the default pool acquired the legacy isolated marker")
GF.HidePreview("party")
assert(default._msufGFPreviewScene == nil, "default release retained its paint owner")
-- Invalidate queued cold work by the same combat hide used by the runtime.
assert(outer:Show(12))
h:EnterCombat()
GF.HidePreviewsForCombat()
h:RunTimers()
assert(not outer:IsActive() and not inner:IsActive(), "queued cold work survived combat release")
assert(held._msufGFPreviewScene == nil and innerFrames[1] == nil, "combat retained an active frame binding")
h:LeaveCombat()
h:RunTimers()
assert(outer:IsActive() and #outer:Frames() == 12 and inner:IsActive(), "combat restore lost per-scene wanted counts")
assert(outer:Frames()[1]._msufGFPreviewScene == outer and inner:Frames()[1]._msufGFPreviewScene == inner,
    "combat restore crossed pool ownership")
outerRoot:Release()
innerRoot:Release()
assert(#h.violations == 0, "preview context test wrote protected geometry")
print("PASS explicit group preview context " .. flavor .. " " .. mode)
