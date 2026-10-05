local root = assert(arg[1], "repository root required")
local path = root .. "/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua"
local chunk = assert(loadfile(path))
local ns = { Client = { IsForever = false } }
chunk("MidnightSimpleUnitFrames", ns)
assert(ns.SwingTimer == nil, "other clients must have no module or events")

local now, combat, native = 100, false, true
local offSpeed, rangedSpeed = 2.5, 2.8
local objects, named, driver = {}, {}
local function noop() end
local methods = {}
for _, name in ipairs({
    "SetMovable", "SetClampedToScreen", "RegisterForDrag", "SetAllPoints",
    "SetJustifyH", "SetBackdropBorderColor", "ClearAllPoints", "SetTextColor", "SetWidth",
    "StopMovingOrSizing", "StartMoving", "SetUpdateInterval", "SetExpiredText", "SetZeroDurationText",
    "SetTexCoord", "SetHeight", "SetClipsChildren",
}) do methods[name] = noop end
function methods:SetMinMaxValues(a,b) self.minimum,self.maximum=a,b end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(v) self.level=v end
function methods:SetOrientation(v) self.orientation=v end
function methods:SetRotatesTexture(v) self.rotatesTexture=v end
function methods:SetHorizTile(v) self.horizTile=v end
function methods:SetVertTile(v) self.vertTile=v end
function methods:GetStatusBarTexture() return self end
function methods:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function methods:SetSize(w,h) self.width, self.height = w,h end
function methods:SetScale(v) self.scale = v end
function methods:GetScale() return self.scale or 1 end
function methods:SetAlpha(v) self.alpha = v end
function methods:GetAlpha() return self.alpha or 1 end
function methods:GetCenter() return self.centerX or 500, self.centerY or 400 end
function methods:SetPoint(...) self.point = {...} end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetFont(...) self.font = {...}; return true end
function methods:SetStatusBarColor(...) self.color = {...} end
function methods:SetStatusBarTexture(v) self.texture = v end
function methods:SetTexture(v) self.texture = v end
function methods:SetBlendMode(v) self.blendMode = v end
function methods:SetVertexColor(...) self.vertexColor = {...} end
function methods:SetReverseFill(v) self.reverse = v end
function methods:SetText(v) self.text = v end
function methods:GetStringWidth() return #(self.text or "") * 7 end
function methods:SetValue(v) self.value = v end
function methods:EnableMouse(v) self.mouse = v end
function methods:SetScript(k,v)
    assert(k ~= "OnUpdate", "no Lua animation/polling driver")
    self.scripts[k] = v
end
function methods:HookScript(k,v) self.hooks[k] = v end
function methods:Show()
    local was = self.shown
    self.shown = true
    if not was and self.hooks.OnShow then self.hooks.OnShow(self) end
end
function methods:Hide() self.shown = false end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown == true end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:RegisterUnitEvent(e,u) assert(u == "player"); self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:SetTimerDuration(d, interpolation, direction)
    self.timer = self.timer or {}
    self.timer.endTime, self.timer.total, self.timer.direction = d.endTime, d.total, direction
end
local function object(name,parent)
    local o = setmetatable({ scripts={}, hooks={}, events={}, name=name, parent=parent, shown=true }, {__index=methods})
    objects[#objects+1] = o
    if name then named[name] = o end
    return o
end
function methods:CreateTexture() return object(nil,self) end
function methods:CreateFontString() return object(nil,self) end
_G.CreateFrame = function(kind,name,parent)
    local o=object(name,parent)
    if kind=="Frame" and not name and not parent then driver=o end
    return o
end
_G.UIParent = object("UIParent")
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return combat end
_G.UnitAffectingCombat = function() return combat end
_G.UnitAttackSpeed = function() return 2, offSpeed, rangedSpeed end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.STANDARD_TEXT_FONT = "test-font"
_G.MSUF_GetFontPath = function() return "global-font" end
_G.GetCVarBool = function(key) assert(key=="showSwingTimer"); return native end
_G.Enum = {
    PlayerSwingType={MainHand=0,OffHand=1,Ranged=2},
    StatusBarTimerDirection={ElapsedTime=0,RemainingTime=1}, StatusBarInterpolation={Immediate=0},
    NumericRuleFormatRounding={Nearest=0}, DurationTextBindingProperty={RemainingDuration=0},
}
_G.C_DurationUtil = {
    CreateDuration=function()
        return { Reset=function(self) self.endTime,self.total=0,0 end,
            SetTimeFromEnd=function(self,e,t) self.endTime,self.total=e,t end }
    end,
    CreateDurationTextBinding=function()
        local b=object()
        function b:SetEnabled(v) self.enabled=v end
        function b:SetFontString(v) self.fontString=v end
        function b:SetDuration(v) self.duration=v end
        function b:SetTextFormat(format,components)
            assert(format=="{}" and components[1].property==0)
        end
        return b
    end,
}
_G.C_StringUtil = { CreateNumericRuleFormatter=function() return {SetBreakpoints=noop} end }
-- Native Forever surfaces used by the range/queued-attack presentation.
local nativeRangeChecks={}
_G.C_SwingTimer={
    EnableRangeCheck=function(hand,enabled) nativeRangeChecks[hand]=enabled end,
    IsTargetWithinSwingRange=function() return nil end,
}
_G.C_Spell={
    GetSpellName=function(id) return ({[78]="Heroic Strike",[845]="Cleave",[6807]="Maul"})[id] end,
    IsCurrentSpell=function() return false end,
}
local nativeFrames={}
for _, name in ipairs({"MainHand","OffHand","Ranged"}) do
    local frame=object()
    function frame:UpdateShownStateAndRegistration() self:SetShown(native); self.receivingSwings=native end
    _G["SwingTimer"..name.."Frame"]=frame
    frame:UpdateShownStateAndRegistration()
    nativeFrames[#nativeFrames+1]=frame
end
local function event(e,...)
    if driver and driver.events[e] then driver.scripts.OnEvent(driver,e,...) end
end
_G.SetCVar = function(key,value)
    assert(key=="showSwingTimer")
    native=value=="1"
    for _, frame in ipairs(nativeFrames) do frame:UpdateShownStateAndRegistration() end
    event("CVAR_UPDATE",key,value)
end
ns.Client.IsForever=true
local textures={
    ["MSUF Smooth"]="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Smooth.tga",
    Custom="Interface\\AddOns\\SharedMedia\\Custom.tga",
}
ns.LSM={
    Fetch=function(_,kind,key) return kind=="statusbar" and textures[key] or nil end,
    List=function(_,kind) return kind=="statusbar" and {"MSUF Smooth","Custom"} or {} end,
    HashTable=function(_,kind) return kind=="statusbar" and textures or {} end,
}
ns.ExportPublic=function(key,value) _G[key]=value end
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua"))("MSUF",ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Modules.lua"))("MSUF",ns)
_G.MSUF_DB={}
chunk("MSUF",ns)
local swing=assert(ns.SwingTimer)
assert(swing.GetEnabled(), "migrate existing native master switch")
assert(not ns.MSUF_GetModule("SwingTimers").__msufEnabled and not named.MSUF_SwingTimer_main,
    "registration and a checked saved preference do not start the module")
assert(driver.events.PLAYER_ENTERING_WORLD, "login must arrange its own module start")
event("PLAYER_ENTERING_WORLD")
assert(ns.MSUF_GetModule("SwingTimers").__msufEnabled, "world entry starts the saved-enabled module without any menu action")
assert(not native, "native manager must stop receiving swings")
local main,off,ranged=named.MSUF_SwingTimer_main,named.MSUF_SwingTimer_off,named.MSUF_SwingTimer_ranged
assert(main:IsShown() and off:IsShown() and not ranged:IsShown(), "both hands by default")
assert(off.Lane == nil, "the off-hand lane is built only when it is chosen")
for _,frame in ipairs(nativeFrames) do
    assert(not frame:IsShown() and not frame.receivingSwings, "all Blizzard bars suppressed")
    -- SwingTimerMixin:SetIsInEditMode sets the field, then shows the bar.
    -- MSUF never hides a Blizzard bar (its OnHide lays out the bottom managed
    -- container tainted); it makes the bar invisible instead.
    frame.isInEditMode = true
    frame:Show()
    assert(frame:IsShown() and frame.alpha == 0, "Edit Mode cannot make a native bar visible")
    -- Edit Mode exit: Blizzard hides the bar itself (the CVar is off).
    frame.isInEditMode = nil
    frame:UpdateShownStateAndRegistration()
    assert(not frame:IsShown(), "harness: Edit Mode exit hides the native bar")
end
event("PLAYER_SWING",2,0)
event("PLAYER_SWING",3,1)
assert(main.Bar.timer.endTime==102 and off.Bar.timer.endTime==103, "hands retain independent durations")
assert(main.binding.enabled and off.binding.enabled)
assert(main.duration~=off.duration)
local oldMain=main.Bar.timer.endTime
assert(swing.Set("off","enabled",false))
assert(main:IsShown() and not off:IsShown() and not native, "main-only still owns every native bar")
event("PLAYER_SWING",8,1)
assert(off.endsAt==nil and main.endsAt==oldMain, "disabled hand ignores swings")
assert(swing.Set("off","enabled",true))
event("PLAYER_SWING",3,1)
offSpeed=nil
event("WEAPON_SLOT_CHANGED")
assert(not off:IsShown() and off.endsAt==nil, "shield/no offhand clears stale timer")
offSpeed=2.5
event("UNIT_ATTACK_SPEED","player")
assert(off:IsShown())
assert(swing.Set("main","visibility","combat"))
assert(not main:IsShown())
event("PLAYER_SWING",2,0)
assert(main.endsAt==102, "first swing is retained before combat visibility")
combat=true
event("PLAYER_IN_COMBAT_CHANGED")
assert(main:IsShown() and main.binding.enabled)
assert(not swing.SetEnabled(false) and not swing.SetPreview(true), "restricted controls fail in combat")
combat=false
event("PLAYER_IN_COMBAT_CHANGED")
assert(not main:IsShown())
assert(swing.Set("ranged","enabled",true))
assert(ranged:IsShown())
event("PLAYER_SWING",4,2)
assert(ranged.endsAt==104)
assert(swing.Set("main","visibility","always"))
assert(swing.Set("main","texture","Custom"))
assert(swing.Set("main","color",{0.1,0.2,0.3}))
assert(swing.Set("main","font","my-font"))
assert(swing.Set("main","fontSize",16))
assert(swing.Set("main","fill","remaining"))
assert(swing.Set("main","direction","LEFT"))
event("PLAYER_SWING",2,0)
assert(main.Bar.texture==textures.Custom and main.Bar.color[2]==0.2)
assert(main.Title.font[1]=="my-font" and main.Time.font[2]==16)
assert(main.Bar.timer.direction==1 and main.Bar.reverse)
assert(swing.Set("off","font",""))
_G.MSUF_GetFontPath=function() return "changed-global-font" end
swing.ApplyFonts()
assert(main.Title.font[1]=="my-font" and off.Title.font[1]=="changed-global-font", "global fonts update only followers")

assert(not swing.Set("main","width",0) and not swing.Set("main","visibility","bogus"))
assert(not swing.Set("main","color",{0/0,0,0}))
assert(swing.SetPreview(true) and main.mouse and main.PreviewBar.value==0.35)
assert(main.PreviewBar:IsVisible() and not main.Bar:IsShown() and not main.PreviewBar.timer,
    "static preview must never inherit the native duration driver")
assert(not driver.events.PLAYER_SWING, "no swing event work while previewing")
assert(main.Time:IsVisible() and main.Time.text=="1.2", "preview text is independent of live bar visibility")
assert(swing.Set("main","fill","elapsed") and main.PreviewBar.value==0.65)
assert(swing.Set("main","texture","Solid"))
assert(main.PreviewBar.texture=="Interface\\Buttons\\WHITE8X8", "built-in choices resolve without Castbars or LSM registration")
assert(swing.Set("main","backgroundTexture","Custom"))
assert(main.PreviewBar.Background.texture==textures.Custom and main.Bar.Background.texture==textures.Custom)
assert(swing.Set("main","backgroundTexture",""))
assert(main.PreviewBar.Background.texture==main.PreviewBar.texture, "background can follow foreground again")
for _,case in ipairs({{"RIGHT","HORIZONTAL",false},{"LEFT","HORIZONTAL",true},{"UP","VERTICAL",false},{"DOWN","VERTICAL",true}}) do
    assert(swing.Set("main","direction",case[1]))
    assert(main.Bar.orientation==case[2] and main.Bar.reverse==case[3])
    assert(main.Bar.rotatesTexture==(case[2]=="VERTICAL"))
    assert(main.PreviewBar.orientation==case[2] and main.PreviewBar.reverse==case[3])
end
assert(not swing.Set("main","direction","invalid") and not swing.Set("main","display","invalid"))
assert(swing.Set("main","time",false))
assert(swing.Set("main","display","text"))
assert(main.Time:IsVisible() and not main.Title:IsVisible() and main.backdrop==nil,
    "number-only overrides hidden remaining time and removes the title and border")
assert(not main.Bar:IsVisible() and not main.PreviewBar:IsVisible(), "number-only removes both bar surfaces and backgrounds")
assert(main.Time.point[1]=="CENTER", "number-only centers the number by default")
assert(swing.Set("main","textAlign","LEFT") and swing.Set("main","textX",7) and swing.Set("main","textY",9))
assert(main.Time.point[1]=="LEFT" and main.Time.point[4]==7 and main.Time.point[5]==9)
assert(swing.SetPreview(false))
local oldBarEnd=main.Bar.timer.endTime
assert(driver.events.PLAYER_SWING)
event("PLAYER_SWING",4,0)
assert(main.binding.enabled and main.duration.endTime==104 and main.Bar.timer.endTime==oldBarEnd,
    "number-only runs only the native text binding")
assert(swing.Set("main","display","bar") and main.Bar.timer.endTime==104)
assert(main.Bar:IsVisible() and not main.Time:IsShown() and main.Title:IsVisible(), "bar mode restores existing title/time choices")
assert(swing.Set("main","time",true))
assert(swing.SetPreview(true))
assert(swing.Set("main","scale",150))
main.centerX,main.centerY=400,300
main.scripts.OnDragStop(main)
assert(swing.Get("main","x")==100 and swing.Get("main","y")==50, "drag persists screen offsets at custom scale")

-- A drag still running when combat starts: the drop is not saved, so the bar
-- stops moving and goes back to its saved place instead of staying dropped.
main.StartMoving = function(self) self.moving = true; self.point = { "DRAGGED" } end
main.StopMovingOrSizing = function(self) self.moving = false end
main.scripts.OnDragStart(main)
assert(main.moving, "a preview drag did not start")
combat=true
event("PLAYER_REGEN_DISABLED")
assert(not swing.GetPreview() and not main.mouse, "combat ends interactive preview")
main.scripts.OnDragStop(main)
assert(not main.moving, "combat start left the bar following the cursor")
assert(swing.Get("main","x")==100 and swing.Get("main","y")==50, "a drop after combat started was saved")
assert(main.point[1]=="CENTER" and math.abs(main.point[2]-100/1.5)<1e-9 and math.abs(main.point[3]-50/1.5)<1e-9,
    "a bar dropped after combat started stays where it was dropped instead of its saved place")
combat=false
-- All three disabled: no PLAYER_SWING subscriber, while ownership remains active.
for _,hand in ipairs({"main","off","ranged"}) do assert(swing.Set(hand,"enabled",false)) end
assert(not driver.events.PLAYER_SWING and not native)
assert(swing.Set("main","enabled",true) and driver.events.PLAYER_SWING)
-- Warm native objects are reused. The modeled event boundary itself allocates nothing.
event("PLAYER_SWING",2,0)
collectgarbage("collect")
collectgarbage("stop")
local before=collectgarbage("count")
for i=1,10000 do event("PLAYER_SWING",2,0) end
local growth=collectgarbage("count")-before
collectgarbage("restart")
assert(growth < 1, "swing hot path allocated "..growth.." KiB")
print("Swing dispatcher allocation smoke: 10000 events, "..growth.." KiB growth (offline stubs)")
local priorDB=_G.MSUF_DB
_G.MSUF_DB={swingTimers={enabled=true,main={width=411,reverse=true}}}
swing.RefreshSettings()
assert(main.width==411 and main.config~=priorDB.swingTimers.main, "enabled-to-enabled profile change rebinds configuration")
assert(main.config.direction=="LEFT" and main.Bar.reverse, "legacy reverse preference migrates once")
_G.MSUF_DB={swingTimers={enabled=false}}
swing.RefreshSettings()
assert(native and next(driver.events)==nil, "profile disabling releases events and restores native preference")
assert(not main:IsShown() and not main.binding.enabled)
for _,frame in ipairs(nativeFrames) do
    assert(frame:IsShown() and frame:GetAlpha() == 1, "release restores the native bars and their alpha")
end
-- An originally hidden native UI must remain hidden on release.
_G.SetCVar("showSwingTimer","0")
assert(swing.SetEnabled(true))
_G.SetCVar("showSwingTimer","1")
assert(not native, "native CVar changes cannot create duplicate bars")
assert(swing.SetEnabled(false) and not native)
_G.SetCVar("showSwingTimer","1")
assert(swing.SetEnabled(true))
event("PLAYER_LOGOUT")
assert(native, "reload restores the original account CVar")
local source=assert(io.open(path,"rb")):read("*a")
assert(not source:find('OnUpdate',1,true) and not source:find('C_Timer',1,true), "native duration animation only")
local profile=assert(io.open(root.."/MidnightSimpleUnitFrames/State/MSUF_ProfileRuntime.lua","rb")):read("*a")
assert(profile:find("MSUF.SwingTimer.Apply()",1,true), "profile fanout includes enabled modules")
print("PASS Forever Swing Timer module: simultaneous hands, native ownership, equipment, native timers, appearance and profile lifecycle")

assert(swing.SetEnabled(false) and swing.SetEnabled(true))
local controls,sections,shortcuts={}, {}, {}
local function bind(_,widget,get,set,meta)
    widget.get,widget.set=get,set
    controls[meta.path]=widget
end
local W={}
function W.PageBuilder()
    return { width=800,y=-100, RequestRelayoutCollapsibles=noop, CollapsibleSection=function(_,id)
        local section=object(); sections[id]=section
        section._msuf2CollapsibleEntry={outer=object(),body=section}
        return section
    end }
end
function W.Toggle() return object() end
W.SectionSwitch=W.Toggle
function W.Segment() local widget=object();widget._msuf2Title=object();return widget end
function W.FixedPreviewSection() return object() end
function W.Slider() return object() end
function W.Dropdown(_,_,values) local widget=object(); widget.values=values; return widget end
function W.Color() error("inline swing color widgets must not be allocated") end
function W.AttachContextColorShortcut(section,options) shortcuts[section]=options end
local page
ns.Require=function(name) assert(name=="MSUF_PixelLayoutRegion");return function(region) return region end end
ns.MSUF2={
    Widgets=W, Theme={Button=function() return object() end},
    UnitSectionsShared={MakeScopeCopyPopup=function() return {Show=noop,Hide=noop} end},
    AdvancedPage={MoveWidget=noop, RegisterControl=noop, ControlMeta=function(_,_,path) return {path=path} end},
    StatusBarTextureItems=ns.UI.StatusBarTextureItems,
    GlobalPage={FontValues=function() return {} end},
    ValueTextList=function(...) local list={}; local args={...}; for i=1,#args,2 do list[#list+1]={value=args[i],text=args[i+1]} end; return list end,
    BindBoolWidget=bind,BindDropdownWidget=bind,BindSegment=bind,
    BindDropdownAt=function(ctx,parent,label,x,y,values,width,get,set,meta)
        local widget=W.Dropdown(parent,label,values,width)
        bind(ctx,widget,get,set,meta)
        return widget
    end,
    TrackRefresh=function(_,refresh) refresh() end,
    BindTextInputAt=function(ctx,parent,label,x,y,width,get,set,commitOnBlur,meta)
        local widget=object(nil,parent);widget.label,widget.commitOnBlur=label,commitOnBlur
        widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);widget:SetWidth(width)
        bind(ctx,widget,get,set,meta);return widget
    end,
    BindNumberWidget=function(ctx,widget,get,set,_,meta) bind(ctx,widget,get,set,meta) end,
    Format=function(text,...) return string.format(text,...) end,
    RegisterPage=function(key,spec) assert(key=="swingtimers"); page=spec end,
    Refresh=noop,
}
assert(loadfile(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_SwingTimersPreview.lua"))("MSUF",ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_SwingTimers.lua"))("MSUF",ns)
page.build({SetContentHeight=noop})
for _,hand in ipairs({"main","off","ranged"}) do
    local targets=shortcuts[sections["swing_"..hand.."_appearance"]].getTargets()
    assert(#targets==3, "appearance context owns bar, background and border colors")
    assert(#shortcuts[sections["swing_"..hand.."_text"]].getTargets()==1, "text context owns text color")
    assert(#shortcuts[sections["swing_"..hand.."_reach"]].getTargets()==1, "reach context owns warning color")
    targets[1].setRGB(.2,.4,.6)
    assert(swing.Get(hand,"color")[2]==.4)
    assert(targets[1].getRGB()==.2, "context color roundtrip")
    local texture=controls[hand..".texture"]
    for _,item in ipairs(texture.values()) do
        assert(item.value==item.texturePreview, "selected texture is the exact preview asset")
        texture.set(item.value)
        assert(texture.get()==item.value and swing.ResolveTexture(swing.Get(hand,"texture"))==item.texturePreview)
        assert(named["MSUF_SwingTimer_"..hand].Bar.texture==item.texturePreview, "menu selection reaches the live surface")
    end
    local background=controls[hand..".backgroundTexture"]
    assert(background.values()[1].value=="", "foreground-follow choice is retained")
    assert(controls[hand..".display"] and controls[hand..".direction"] and controls[hand..".textAlign"])
end
for _,key in ipairs({"offhandLane","nextSwingCue"}) do
    local control=assert(controls["main."..key], key .. " control missing")
    control.set(false);assert(control.get()==false and swing.Get("main",key)==false, key .. " roundtrip")
    control.set(true);assert(control.get()==true, key .. " roundtrip")
end
for _,hand in ipairs({"main","off","ranged"}) do
    for _,key in ipairs({"reachCheck","reachOpacity"}) do
        assert(controls[hand.."."..key], hand .. " " .. key .. " control missing")
    end
end
-- The cue text switch and one text per next-swing attack, labelled with the
-- client's spell name (the attack's spell ID where the client has no name).
local cueText=assert(controls["main.nextSwingText"], "the cue text switch is missing")
cueText.set(true);assert(cueText.get()==true and swing.Get("main","nextSwingText")==true, "cue text switch roundtrip")
cueText.set(false)
for id,name in pairs({[78]="Heroic Strike",[845]="Cleave",[6807]="Maul",[2973]="2973"}) do
    local input=assert(controls["main.nextSwingLabel"..id], "the cue text for "..id.." is missing")
    assert(input.label:find(name,1,true) and input.commitOnBlur==true, "the cue text for "..id.." is not labelled with its attack")
    input.set("Go");assert(input.get()=="Go" and swing.Get("main","nextSwingLabel"..id)=="Go", "cue text roundtrip "..id)
    input.set("");assert(swing.Get("main","nextSwingLabel"..id)=="", "clearing a cue text "..id)
end
assert(#shortcuts[sections.swing_next].getTargets()==1, "main-hand cue context owns its color")
print("PASS Swing menu: scoped appearance, text, reach and main-hand cue color menus, real shared media paths, number-only/direction, off-hand lane, reach, next-swing and per-attack cue text controls")

-- A fresh login with the feature disabled must leave no subscriber behind.
assert(swing.SetEnabled(false))
local disabledNS={Client={IsForever=true},ExportPublic=ns.ExportPublic,LSM=ns.LSM,UI=ns.UI}
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Modules.lua"))("MSUF",disabledNS)
_G.MSUF_DB={swingTimers={enabled=false}}
chunk("MSUF",disabledNS)
local disabledDriver=driver
local beforeWorldObjects=#objects
assert(disabledDriver.events.PLAYER_ENTERING_WORLD)
event("PLAYER_ENTERING_WORLD")
assert(next(disabledDriver.events)==nil and not disabledDriver.scripts.OnEvent,
    "disabled login removes the one-shot startup handler")
assert(#objects==beforeWorldObjects, "disabled login does not build bars, bindings or formatters")
assert(not disabledNS.MSUF_GetModule("SwingTimers").__msufEnabled)
assert(disabledNS.SwingTimer.SetEnabled(true) and driver==disabledDriver,
    "enabling later reuses the startup driver")
assert(driver.events.PLAYER_SWING and named.MSUF_SwingTimer_main:IsShown() and not native)
assert(disabledNS.SwingTimer.SetEnabled(false))
print("PASS Swing login: saved-enabled starts on world entry; saved-disabled has no bars or idle events; later enable reuses driver")
