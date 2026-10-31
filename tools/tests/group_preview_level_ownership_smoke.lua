-- An embedded preview's level band belongs to its frame, including nested
-- layout sinks, default previews, and a caught inner compile failure.
local root, flavor, mode = assert(arg[1]), arg[2] or "Mainline", arg[3] or "nested"
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, flavor, { beforeBoot = function(world) world.env.MAX_BOSS_FRAMES = 5 end })
local GF, Layers = h.GF, h.core.UF.Layers
GF.EnsureDB()
h.core.ExportPublic("MSUF2_GFPagePreviewActive", true)
local function New(level, unit)
    local parent = h.env.CreateFrame("Frame", nil, h.env.UIParent)
    parent:SetSize(400, 250)
    local owner = GF.NewPreviewScene(parent)
    local group
    if unit then
        group = owner:Unit("target")
        group.level = level
        group:Show()
    else
        group = owner:Group("party", 1)
        group:Configure({ level = level })
    end
    owner:Activate()
    h:RunTimers()
    return owner, group, assert(unit and group:Frame() or group:Frames()[1])
end
local outerRoot, outer, frame = New(500, mode == "unit-group")
local innerRoot, inner, innerFrame = New(900, mode == "group-unit")
local textHost = assert(frame.nameText:GetParent())
local expected = textHost:GetFrameLevel()
assert(expected >= 600, "outer level-band control was not applied")
local bar, entered = frame.hpBar, false
local point, compile = bar.SetPoint, GF.CompileSpec
bar.SetPoint = function(self, ...)
    if not entered then
        entered = true
        innerFrame._msufGFPreviewApplyKey = nil
        if mode == "error" then
            GF.CompileSpec = function(kind, target, ...)
                if target == innerFrame then error("inner scene compile failure") end
                return compile(kind, target, ...)
            end
            local ok, why = pcall(inner.Refresh, inner, { immediate = true })
            GF.CompileSpec = compile
            assert(not ok and tostring(why):find("inner scene compile failure", 1, true), "compile-failure control did not run")
        elseif mode == "default" then
            assert(GF.ShowPreview("party", 1, { immediate = true }))
        else
            assert(inner:Refresh({ immediate = true }))
        end
    end
    return point(self, ...)
end
frame._msufGFPreviewApplyKey = nil
bar._msufHealthPowerInset = nil
assert(outer:Refresh({ immediate = true }))
bar.SetPoint = point
assert(entered, "real Health.Layout did not reach the nested geometry sink")
assert(textHost:GetFrameLevel() == expected, "nested apply replaced the outer frame's level band")
if mode == "default" then
    local default = assert(GF._previewFrames.party[1])
    assert(default.nameText:GetParent():GetFrameLevel() == expected - 500,
        "default preview inherited an embedded scene's level band")
    GF.HidePreview("party")
end
assert(Layers.ElementLevel(0, 0, 0) == 100, "scene paint changed the live/Suite element-level contract")
assert(inner:Refresh({ immediate = true }) and outer:Refresh({ immediate = true }))
assert(textHost:GetFrameLevel() == expected, "interleaved refresh lost the outer level band")
-- Clearing the optional level restores the ordinary base on the next spec
-- apply, including a frame already cached at a raised level.
if mode == "unit-group" then outer.level = nil else outer:SetLevel(nil) end
assert(outer:Refresh({ immediate = true }))
assert(textHost:GetFrameLevel() == expected - 500, "clearing the scene level retained its old element band")
outerRoot:Release()
innerRoot:Release()
assert(#h.violations == 0, "level ownership test wrote protected geometry")
print("PASS group preview level ownership " .. flavor .. " " .. mode)
