local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root..'/tools/tests/menu_core_world.lua'))()
local Open = assert(loadfile(root..'/tools/tests/menu_l4_world.lua'))()
local mw = Open(root,flavor,{page='home',clientScriptBindings=true,tocMetadata=true,
    beforeCore=function(world) MW.InstallNativeUnitInputs(world) end})
local M, env = mw.M, mw.world.env
for _, key in ipairs({ "focusCastbarOverrideEnabled", "focusCastbarOverrideColor" }) do
    assert(mw.core.ProfileFields.GeneralOwner(key) == "castbarColors", "focus color must belong to castbar color exports: " .. key)
    assert(mw.core.ProfileFields.GeneralSyncOwner(key) == "castbars", "focus color lost castbar sync ownership")
end
local factory = assert(mw.core.ProfileFields.CopySnapshot(M.EnsureDB()))
mw.core.MSUF_CreateFactoryDefaultProfile = function() return assert(mw.core.ProfileFields.CopySnapshot(factory)) end
mw.core.PublicGlobals.MSUF_CreateFactoryDefaultProfile = mw.core.MSUF_CreateFactoryDefaultProfile
local function Settle()
    for i=1,30 do
        if #mw.world.widgets.timers==0 then break end
        mw:RunTimers(1000)
    end
    M.Theme.StopAllMenuAnimations()
end
local function Control(suffix)
    suffix=suffix:gsub('_','.')
    for _,w in ipairs(M.cache.opt_colors.searchWidgets) do
        local r=w._msuf2RuntimeControlRecord
        if r and r.controlId:sub(-#suffix)==suffix then return w end
    end
    for _,w in ipairs(M.cache.opt_colors.searchWidgets) do
        local r=w._msuf2RuntimeControlRecord
        if r and r.controlId:find('cast') then print('SEEN',r.controlId) end
    end
    error('missing control '..suffix..'\n'..table.concat(mw.world.reported,'\n'))
end
assert(mw:Select('opt_colors')~=false)
Settle()
M.ColorsSetPainterCategory('cast');Settle()
local enable=Control('castbar.focus_override.enabled')
local swatch=Control('castbar.focus_override.custom_color')
local reset=Control('castbar.reset')
local function General() return env.MSUF_DB.general end
assert(General().focusCastbarOverrideEnabled~=true,'new default unexpectedly enabled')
assert(swatch._msuf2DesiredEnabled==false and not swatch:IsEnabled(),'swatch enabled for absent toggle')
MW.FireScript(enable,'OnClick','LeftButton');Settle()
assert(General().focusCastbarOverrideEnabled==true,'menu toggle failed')
assert(swatch._msuf2DesiredEnabled==true and swatch:IsEnabled(),'swatch stays disabled after toggle')
assert(M.Undo());Settle()
assert(General().focusCastbarOverrideEnabled~=true,'toggle Undo failed')
assert(not swatch:IsEnabled(),'Undo failed to disable swatch')
assert(M.Redo());Settle()
assert(General().focusCastbarOverrideEnabled==true,'toggle Redo failed')
assert(swatch:IsEnabled(),'Redo failed to enable swatch')
swatch._msuf2OnColorChanged(.17,.29,.43);Settle()
local c=General().focusCastbarOverrideColor
assert(c and c[1]==.17 and c[2]==.29 and c[3]==.43,'swatch failed')
assert(M.Undo());Settle()
assert(General().focusCastbarOverrideColor==nil,'swatch Undo did not restore absent state')
assert(M.Redo());Settle()
assert(General().focusCastbarOverrideColor[1]==.17,'swatch Redo failed')
MW.FireScript(reset,'OnClick','LeftButton');Settle()
assert(General().focusCastbarOverrideEnabled==false and General().focusCastbarOverrideColor==nil,'cast reset failed')
assert(M.Undo());Settle()
assert(General().focusCastbarOverrideEnabled==true and General().focusCastbarOverrideColor[2]==.29,'reset Undo failed')
assert(M.Redo());Settle()
assert(General().focusCastbarOverrideEnabled==false and General().focusCastbarOverrideColor==nil,'reset Redo failed')
local context=assert(M.ResolveContextColorReferences('cast.focus_override')[1])
local saved=context.captureState()
context.setRGB(.21,.32,.43);Settle()
assert(General().focusCastbarOverrideColor[1]==.21,'context swatch failed')
context.restoreState(saved);Settle()
assert(General().focusCastbarOverrideColor==nil,'context Cancel failed to remove originally absent table')
MW.FireScript(enable,'OnClick','LeftButton');Settle()
swatch._msuf2OnColorChanged(.17,.29,.43);Settle()
local r,green,b=mw.world.core.Castbars.Utils.ResolveCastbarColors('focus')
assert(r==.17 and green==.29 and b==.43,'menu apply did not invalidate the runtime color snapshot')
assert(M.ResetPageToDefaults('opt_colors'));Settle()
assert(General().focusCastbarOverrideEnabled~=true and General().focusCastbarOverrideColor==nil,'Colors page reset missed focus fields')
assert(M.Undo());Settle()
assert(General().focusCastbarOverrideEnabled==true and General().focusCastbarOverrideColor[1]==.17,'page reset Undo lost focus state')
for _,message in ipairs(mw.world.reported) do
    assert(message=='MSUF Auras3: Blizzard_AuraContainer is not loaded: MISSING',message)
    print('Fixture limitation: native Blizzard_AuraContainer is not installed in MenuWorld')
end
print('PASS focus color menu: toggle/swatch/reset Undo+Redo and absent-state restoration')
