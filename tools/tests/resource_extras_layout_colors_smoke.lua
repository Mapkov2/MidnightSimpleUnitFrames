local root,flavor=assert(arg[1]),arg[2] or "Mainline"
local MenuWorld=assert(loadfile(root.."/tools/tests/menu_core_world.lua"))()
local mw=MenuWorld.Open(root,flavor,{page="classpower"})
local M,W=mw.M,mw.M.Widgets
local ui=M.ClassPowerWorkspace.current
local bars=mw.env.MSUF_DB.bars
local function Check(ok,message) assert(ok,flavor..": "..message) return ok end
local function Find(key)
    for _,control in ipairs(mw.world.widgets.frames) do
        local meta=control._msuf2SearchMeta
        local command=control._msuf2CommandAction
        if meta and (meta.settingKey==key or meta.controlId==key)
            or command and (command.controlId==key or command.settingKey==key) then return control end
    end
end
local sections=M.cache.classpower.sections
local _,built=M.ResourceExtrasPage.ClientOnlySettings()
local midnight=built["bars.showIgnorePain"]==true
Check((sections.classpower_resource_pain~=nil)==midnight,"Ignore Pain section client gate")
Check((sections.classpower_resource_arcane~=nil)==midnight,"Arcane section client gate")
Check((sections.classpower_resource_layout~=nil)==midnight,"duration layout client gate")
Check(sections.classpower_resource_extras and sections.classpower_resource_marks,"shared sections missing")
if midnight then
    local section=sections.classpower_resource_arcane
    local entry=section._msuf2CollapsibleEntry
    Check(entry.featureSwitch,"collapsed Arcane has no master switch")
    Check(entry.header._msuf2ContextColorShortcut,"collapsed Arcane has no color shortcut")
    local _,_,_,x=entry.featureSwitch:GetPoint()
    Check(x<=-50,"header shortcut overlaps the master switch")
    Check(not Find("bars.arcaneWindowWarnSeconds"),"cold collapsed Arcane built its body")
    local enabled=bars.showArcaneWindow
    entry.featureSwitch:SetChecked(true)
    entry.featureSwitch:GetScript("OnClick")(entry.featureSwitch)
    Check(bars.showArcaneWindow==true,"collapsed master cannot enable its effect")
    bars.showArcaneWindow=enabled
    Check(not Find("bars.arcaneWindowWarnSeconds"),"master click built the closed body")
end
ui:Select("extras")
for _,entry in ipairs(ui.entries.extras) do entry.SetOpenImmediate(true) end
mw:RunTimers()
for _,entry in ipairs(ui.entries.extras) do
    Check(entry.outer:IsShown(),"extra section was classified as Class Resource")
    Check(entry.body._msuf2ControlCards and #entry.body._msuf2ControlCards>0,"plain ungrouped extra body")
end
local captured
W.OpenColorContextPicker=function(title,owners) captured=owners end
local mana=sections.classpower_resource_extras._msuf2CollapsibleEntry.header._msuf2ContextColorShortcut
Check(mana,"Mana shortcut missing"):GetScript("OnClick")(mana)
local regen=built["bars.manaGainPulse"]==true
Check(captured and #captured==(regen and 3 or 1),"Mana shortcut has wrong client colors")
local owner=captured[#captured]
local original=owner:_msuf2CaptureColorState()
local enabled=bars.manaUpcomingCost
owner._msuf2OnColorChanged(.21,.32,.43)
Check(bars.manaCostColor[1]==.21 and bars.manaUpcomingCost==enabled,"shortcut writes the wrong setting")
owner:_msuf2RestoreColorState(original)
Check(not original.color and not bars.manaCostColor or original.color and bars.manaCostColor[1]==original.color[1],"Cancel creates an override")
local add=Check(Find("menu2.classpower.advanced.resource.extras.marks.add"),"mark add missing")
add:GetScript("OnClick")(add)
mw:RunTimers()
local first=bars.resourceMarks[#bars.resourceMarks]
add:GetScript("OnClick")(add)
mw:RunTimers()
local rule=bars.resourceMarks[#bars.resourceMarks]
local mark=sections.classpower_resource_marks._msuf2CollapsibleEntry.header._msuf2ContextColorShortcut
Check(mark and mark:IsShown(),"selected mark has no shortcut")
mark:GetScript("OnClick")(mark)
Check(captured and #captured==1,"mark shortcut target missing")
captured[1]._msuf2OnColorChanged(.15,.25,.35)
Check(rule.color[1]==.15,"mark shortcut changes another rule")
mw:Select("opt_colors")
local colors=M.cache.opt_colors
local resolve=M.GetMissingSectionResolver(colors)
Check(type(resolve)=="function","Colors has no cold section resolver")
local extras=Check(resolve("colors_resource_extras"),"cold color search does not open Resources")
Check(extras._msuf2CollapsibleEntry,"extra colors are not a proper section")
Check(resolve("colors_resource_marks"),"mark colors missing in Resources")
local color=Check(Find("menu2.colors.advanced.resource.extras.marks.color"),"canonical mark color missing")
color._msuf2OnColorChanged(.46,.56,.66)
Check(rule.color[1]==.46,"Colors and shortcut have separate mark storage")
Check(first.color[1]~=rule.color[1],"editing a selected color changes other marks")
for _,key in ipairs({"ignorePainColor","arcaneWindowColor","arcaneWindowSoulColor","arcaneWindowWarnColor",
    "manaRegenPauseColor","manaGainPulseColor","manaCostColor"}) do
    local available=not key:find("^ignorePain") and not key:find("^arcane") and not key:find("^manaRegen") and not key:find("^manaGain")
        or built["bars."..key]
    Check((Find("bars."..key)~=nil)==(available and true or false),"canonical color gate: "..key)
end
mw:Select("classpower")
ui:Select("extras")
mark:GetScript("OnClick")(mark)
Check(select(1,captured[1]:GetRGB())==.46,"shortcut did not refresh after canonical editing")
local saved=bars.resourceMarks
bars.resourceMarks={first}
M.RequestRefresh(ui.page.ctx,"profile-restore")
mw:RunTimers()
Check(M.ResourceExtrasPage.MarkRule(function() return bars end)==first,"profile restore keeps an unavailable mark index")
bars.resourceMarks=saved
print(flavor..": additional resource accordion/color workflow PASS")
