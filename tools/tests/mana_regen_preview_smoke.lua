local root, flavor = assert(arg[1]), arg[2] or "Forever"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, {page="classpower",beforeOptions=function(world)
    world.env.C_DurationUtil = {CreateDuration=function() return MenuWorld.Stub end}
end})
local M, env = mw.M, mw.env
local ui = assert(M.ClassPowerWorkspace.current)
local box = ui.page.ctx.entry.classPowerPreview
local bars = env.MSUF_DB.bars
ui:Select("extras")
for _, entry in ipairs(ui.entries.extras) do entry.SetOpenImmediate(true) end
mw:RunTimers()
M.ResourceExtrasPreview.Select("pulse")
local function Control(path)
    for _, frame in ipairs(mw.world.widgets.frames) do
        local meta = frame._msuf2SearchMeta
        if meta and meta.settingKey == path then return frame end
    end
    error("missing actual control "..path)
end
local styleControl = Control("bars.manaRegenStyle")
local widthControl, glowControl = Control("bars.manaRegenSparkWidth"), Control("bars.manaRegenSparkAlpha")
widthControl:GetScript("OnValueChanged")(widthControl,5)
glowControl:GetScript("OnValueChanged")(glowControl,.6)
assert(bars.manaRegenSparkWidth==5 and bars.manaRegenSparkAlpha==.6,"sliders did not persist")
local function Under(frame, parent)
    while frame do if frame == parent then return true end frame=frame:GetParent() end
end
for _, style in ipairs({"spark","bars","spark"}) do
    styleControl._msuf2OnValueChanged(style)
    assert(bars.manaRegenStyle==style,"style control did not persist")
    box:Refresh()
    local found = false
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame.markerReady and frame:IsShown() and Under(frame,box) then
            found=true
            assert(frame.markerStyle==style,"menu preview has another marker style")
            if style=="spark" then
                assert(frame.manaSpark:IsShown() and frame.manaSpark:GetWidth()==5,"menu preview ignores width")
                local _,_,_,alpha=frame.manaGlow:GetVertexColor()
                assert(alpha==.6,"menu preview ignores glow")
            else assert(frame:GetHeight()==2 or frame:GetHeight()==3,"menu preview lost separate strips") end
        end
    end
    assert(found,"menu preview has no mana regeneration indicator")
end
assert(bars.manaRegenStyle=="spark" and bars.manaRegenSparkWidth==5 and bars.manaRegenSparkAlpha==.6)
print("mana_regen_preview_smoke: "..flavor.." styles/width/glow PASS")
