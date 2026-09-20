-- End-to-end portrait settings: saved config -> compiler -> live elements and preview.
local root, flavor = assert(arg[1]), arg[2] or "Forever"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env, core = world.env, world.core
local function near(a,b,label)
    assert(type(a)=="number" and math.abs(a-b)<1e-6, (label or "value")..": "..tostring(a).." ~= "..tostring(b))
end
env.UnitExists=function() return true end
env.UnitIsVisible=function() return true end
env.UnitIsConnected=function() return true end
env.UnitGUID=function() return "Player-PortraitSettings" end
env.UnitClass=function() return "Mage","MAGE" end
local casting=false
env.UnitCastingInfo=function() if casting then return "Test Cast",nil,12345 end end
env.UnitChannelInfo=function() return nil end
env.InCombatLockdown=function() return false end
-- Model the native resolver rebinding a portrait and resetting texture coords.
-- A cached crop must also survive this on an explicit portrait/model update.
local resolves=0
env.SetPortraitTexture=function(texture,unit,unmasked)
    resolves=resolves+1
    texture:SetTexture("portrait:"..unit)
    texture:SetTexCoord(0,1,0,1)
    texture.unmasked=unmasked
end
world:Boot()
local failure=world:FirstFailure()
assert(not failure, failure and failure.message)
local UF=core.UF
env.MSUF_InitProfiles()
env.MSUF_EnsureDB(true)
local conf=env.MSUF_DB.player
conf.portraitMode="LEFT"
conf.portraitRender="2D"
conf.portraitClickable=false
conf.portraitSizeMode="UNIFORM"
conf.portraitSizeOverride=60
conf.portraitCastSpellIcon=false
conf.oocFadeEnabled=false
conf.rangeFadeEnabled=false
conf.hpBarAlpha=.6
conf.alphaExcludeTextPortrait=true
local frame=env.CreateFrame("Frame",nil,env.UIParent)
frame:SetSize(240,44)
frame:SetFrameLevel(20)
frame.MSUFUnitKey="player"
frame.Health=env.CreateFrame("StatusBar",nil,frame)
frame.Health:SetSize(240,44)
frame.Health:SetFrameLevel(21)
frame.hpBar=frame.Health
local portrait,alpha=UF.elements.Portrait,UF.elements.Alpha
assert(portrait and alpha)
local function apply()
    UF.Config.Refresh()
    local spec=assert(UF.Config.GetSpec("player"))
    frame.MSUFSpec=spec
    portrait.Apply(frame,spec)
    alpha.Apply(frame,spec)
    return spec.portrait
end
local function crop(p)
    local c=frame.portrait.texCoord
    near(c[1],p.texL,"left crop"); near(c[2],p.texR,"right crop")
    near(c[3],p.texT,"top crop"); near(c[4],p.texB,"bottom crop")
end
for _,shape in ipairs({"BLIZZARD","CIRCLE","SQUARE","ROUNDED","DIAMOND"}) do
    conf.portraitShape=shape
    for _,opacity in ipairs({100,37,0,100}) do
        conf.portraitAlpha=opacity
        local p=apply()
        near(frame.MSUFPortraitHolder:GetAlpha(),opacity/100,shape.." own opacity")
        conf.alphaExcludeTextPortrait=false
        apply()
        near(frame.MSUFPortraitHolder:GetAlpha(),opacity/100*.6,shape.." bar opacity composition")
        portrait.Apply(frame,frame.MSUFSpec)
        near(frame.MSUFPortraitHolder:GetAlpha(),opacity/100*.6,"portrait-only reapply")
        alpha.Disable(frame)
        near(frame.MSUFPortraitHolder:GetAlpha(),opacity/100,"alpha reset retains portrait opacity")
        conf.alphaExcludeTextPortrait=true
    end
    for _,layer in ipairs({0,1,7,30,0}) do
        conf.portraitLevelOffset=layer
        apply()
        local holder=frame.MSUFPortraitHolder
        if layer==0 then
            assert(holder:GetFrameLevel()<frame.Health:GetFrameLevel(),"layer 0 below health")
            assert(holder.border:GetFrameLevel()<frame.Health:GetFrameLevel(),"rim below health")
        else
            near(holder:GetFrameLevel(),UF.Layers.ElementLevel(layer,7,0),"shared portrait layer")
            near(holder.border:GetFrameLevel(),holder:GetFrameLevel()+1,"rim layer")
        end
    end
    for _,zoom in ipairs({100,110,150,200}) do
        for _,pan in ipairs({-100,0,100}) do
            conf.portraitZoom=zoom; conf.portraitPanX=pan; conf.portraitPanY=-pan
            local p=apply(); crop(p)
            assert(p.texL>=-1e-12 and p.texR<=1+1e-12 and p.texT>=-1e-12 and p.texB<=1+1e-12,"bounded crop")
            if shape=="BLIZZARD" and zoom==100 then
                near(frame.portrait._msufImageX,-pan/100*.08*60,"unzoomed Blizzard pan X")
                near(frame.portrait._msufImageY,pan/100*.08*60,"unzoomed Blizzard pan Y")
            end
            -- Track the same point of the image: pan axes must keep their
            -- direction when crossing from full-image translation into UV crop.
            if pan~=0 then
                local featureX=((.5-p.texL)/(p.texR-p.texL)-.5)*60+frame.portrait._msufImageX
                local featureY=(.5-(.5-p.texT)/(p.texB-p.texT))*60+frame.portrait._msufImageY
                assert(featureX*pan<0 and featureY*pan>0,"pan direction across zoom")
            end
            local before=resolves
            frame._msufPortraitForceRefresh=true
            portrait.Apply(frame,frame.MSUFSpec)
            assert(resolves==before+1,"forced native refresh")
            crop(p)
            portrait.Apply(frame,frame.MSUFSpec)
            assert(resolves==before+1,"unchanged apply must not re-render native portrait")
            assert(frame.MSUFPortraitHolder.mask.allPoints==frame.MSUFPortraitHolder,"mask must not move with image")
        end
    end
end
-- Geometry, placement, background and render switches on a reused holder.
conf.portraitShape="BLIZZARD"
conf.portraitZoom=100; conf.portraitPanX=100; conf.portraitPanY=100
conf.portraitSizeMode="SEPARATE"; conf.portraitWidth=80; conf.portraitHeight=48
conf.portraitBgEnabled=true
conf.portraitOffsetX=11; conf.portraitOffsetY=-9
for _,placement in ipairs({"ATTACHED","DETACHED","OVERLAY"}) do
    conf.portraitPlacement=placement
    conf.portraitDetachedPoint="TOPLEFT"; conf.portraitDetachedTo="BOTTOMRIGHT"
    conf.portraitOverlayAlign="CENTER"
    local p=apply(); local holder=frame.MSUFPortraitHolder
    near(holder:GetWidth(),80,"separate width"); near(holder:GetHeight(),48,"separate height")
    assert(holder.bg:IsShown(),"background on")
    local point,_,relative,x,y=holder:GetPoint(1)
    near(x,11,"placement X"); near(y,-9,"placement Y")
    if placement=="DETACHED" then assert(point=="TOPLEFT" and relative=="BOTTOMRIGHT") end
    if placement=="OVERLAY" then assert(point=="CENTER" and relative=="CENTER") end
end
conf.portraitRender="CLASS"
apply()
near(frame.portrait._msufImageX,0,"class art ignores 2D pan")
near(frame.portrait._msufImageY,0,"class art ignores 2D pan")
conf.portraitBgEnabled=false; conf.portraitMode="OFF"
apply(); assert(not frame.MSUFPortraitHolder:IsShown(),"portrait off")
conf.portraitMode="RIGHT"; conf.portraitRender="2D"
conf.portraitPlacement="ATTACHED"; conf.portraitSizeMode="UNIFORM"
conf.portraitAlpha=37; conf.portraitLevelOffset=0
conf.portraitOffsetX=0; conf.portraitOffsetY=0
apply(); assert(frame.MSUFPortraitHolder:IsShown(),"portrait on")
assert(not frame.MSUFPortraitHolder.bg:IsShown(),"background off")
-- Cast icons and click targets keep the fixed contour while image pan is active.
conf.portraitCastSpellIcon=true; casting=true
apply()
assert(frame.MSUFPortraitCastIcon:IsShown() and not frame.portrait:IsShown(),"cast icon replacement")
assert(frame.MSUFPortraitCastIcon.allPoints==frame.MSUFPortraitHolder,"cast icon ignores image pan")
casting=false; apply()
assert(not frame.MSUFPortraitCastIcon:IsShown() and frame.portrait:IsShown(),"cast restores portrait")
conf.portraitClickable=true; apply()
local click=assert(frame.MSUFPortraitClickTarget)
assert(click.allPoints==frame.MSUFPortraitHolder and click:IsShown(),"click target follows holder")
assert(click:GetAttribute("useparent*")==true and click:GetAttribute("useparent-unit")==true,"inherited secure actions")
conf.portraitClickable=false; apply(); assert(not click:IsShown(),"click target disabled")
-- Build the actual menu preview and compare its settings to the compiled spec.
local Methods=world.widgets.Methods
for _,name in ipairs({"SetStartPoint","SetEndPoint","SetThickness","SetAutoFocus","SetMaxLetters","EnableKeyboard","SetValueStep","SetNumeric"}) do
    if not Methods[name] then Methods[name]=function() end end
end
local parent=env.CreateFrame("Frame",nil,env.UIParent); parent:SetSize(900,400)
local panel=env.CreateFrame("Frame",nil,env.UIParent)
panel._msufGetCurrentKey=function() return "player" end
local Preview=assert(core.UFPreview)
local box=Preview._BuildPreview(parent,panel,900,400)
box:Show(); box.canvas:SetSize(400,200)
for _,layer in ipairs({0,7,30}) do
    conf.portraitLevelOffset=layer
    apply(); Preview.Refresh(box,"PORTRAIT_SETTINGS_SMOKE")
    local mock=box.mock
    near(mock.portrait:GetAlpha(),.37,"preview own opacity")
    if layer==0 then
        assert(mock.portrait:GetFrameLevel()<mock.healthBar:GetFrameLevel(),"preview layer 0")
        assert(mock.portrait.border:GetFrameLevel()<mock.healthBar:GetFrameLevel(),"preview rim layer 0")
    else near(mock.portrait:GetFrameLevel(),UF.Layers.ElementLevel(layer,7,0),"preview layer") end
    assert(mock.portrait.tex._msufImageX<0 and mock.portrait.tex._msufImageY<0,"preview unzoomed pan")
end
-- Party uses its real compiler and the same live portrait/alpha elements.
local group=env.MSUF_DB.gf_party
for k,v in pairs({portraitMode="LEFT",portraitRender="2D",portraitShape="CIRCLE",
 portraitSizeOverride=40,portraitAlpha=40,portraitLevelOffset=0,portraitBorderStyle="NONE",
 hpBarAlpha=.5,alphaExcludeTextPortrait=false,portraitClickable=false}) do group[k]=v end
core.GF.InvalidateCompiledSpecs("party")
local groupSpec=core.GF.CompileSpec("party",nil,"party1")
frame.MSUFSpec=groupSpec; frame.MSUFUnitKey="party1"
portrait.Apply(frame,groupSpec); alpha.Apply(frame,groupSpec)
near(frame.MSUFPortraitHolder:GetAlpha(),.2,"party composed opacity")
assert(frame.MSUFPortraitHolder.border:GetFrameLevel()<frame.Health:GetFrameLevel(),"party layer 0")
local groupMock=env.CreateFrame("Frame",nil,env.UIParent)
groupMock:SetSize(180,48); groupMock:SetFrameLevel(500)
groupMock._health=env.CreateFrame("StatusBar",nil,groupMock); groupMock._health:SetFrameLevel(501)
local scene={kind="party",mock=groupMock,runtimeSpec=groupSpec,layerAvailable={},layerVisible={},
 previewScale=1,liveData={class="MAGE"},box={},MSUF=core,
 S={Layers=UF.Layers,ScaleValue=function(v,scale) return v*scale end,ClassColor=function() return 1,1,1 end}}
core.MSUF2.GroupPreviewRender.PaintGroupPreviewPortrait(scene)
local groupPortrait=assert(groupMock._msufGroupPortrait)
near(groupPortrait:GetAlpha(),.2,"party preview composed opacity")
assert(groupPortrait.border:GetFrameLevel()<groupMock._health:GetFrameLevel(),"party preview layer 0")
-- The new opt-in survives the real client compiler, classification events,
-- target identity changes and the final preview pass on every client flavor.
assert(conf.portraitBlizzardElite == false, "dragon default must be opt-in")
conf.portraitMode="LEFT"; conf.portraitRender="2D"; conf.portraitShape="BLIZZARD"
conf.portraitSizeMode="UNIFORM"; conf.portraitSizeOverride=60
conf.portraitBlizzardElite=true; conf.portraitCastSpellIcon=false
frame.MSUFUnitKey="player"
local classification="elite"
env.UnitClassification=function() return classification end
local gold="UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"
local silver="ui-hud-unitframe-target-portraiton-boss-rare-silver"
local winged="UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged"
env.C_Texture=env.C_Texture or {}
env.C_Texture.GetAtlasInfo=function(atlas)
    if atlas==gold or atlas==silver or atlas==winged then return {width=80,height=90} end
end
local compiled=apply()
assert(compiled.blizzardElite==true,"compiler must retain opt-in")
local dragon=assert(frame.MSUFPortraitHolder.blizzElite,"live elite dragon")
assert(dragon.atlas==gold and dragon:IsShown(),"gold elite dragon")
for _,state in ipairs({"rareelite","rare","worldboss","normal","elite"}) do
    classification=state
    local before=resolves
    portrait.Update(frame,"UNIT_CLASSIFICATION_CHANGED","player")
    assert(resolves==before,"classification event must not resolve native portrait")
    local expected=state=="worldboss" and winged or (state=="elite" and gold)
        or ((state=="rare" or state=="rareelite") and silver)
    assert(dragon:IsShown()==not not expected,"live classification visibility")
    if expected then assert(dragon.atlas==expected,"live classification art") end
    Preview.Refresh(box,"PORTRAIT_DRAGON_SMOKE")
    local previewDragon=box.mock.portrait.blizzElite
    if expected then
        assert(previewDragon and previewDragon:IsShown() and previewDragon.atlas==expected,"preview classification art")
        assert(previewDragon:GetParent()==box.mock.portrait,"preview dragon must avoid hidden geometric border parent")
    else assert(not previewDragon or not previewDragon:IsShown(),"normal preview hides dragon") end
end
classification="rareelite"
portrait.Update(frame,"MSUF_UNIT_IDENTITY_VISUAL","player")
assert(dragon.atlas==silver and dragon:IsShown(),"identity refresh updates decoration")
conf.portraitBlizzardElite=false
apply(); Preview.Refresh(box,"PORTRAIT_DRAGON_OFF")
assert(not dragon:IsShown() and not box.mock.portrait.blizzElite:IsShown(),"toggle clears both renderers")
conf.portraitBlizzardElite=true; conf.portraitShape="CIRCLE"
apply(); Preview.Refresh(box,"PORTRAIT_DRAGON_OTHER_SHAPE")
assert(not dragon:IsShown() and not box.mock.portrait.blizzElite:IsShown(),"other shapes clear decoration")
-- Runtime preview uses the actual frame registry and clears its sample on stop.
conf.portraitShape="BLIZZARD"; conf.portraitBlizzardElite=true
classification="normal"; apply()
local priorFrameList=UF.frameList
UF.frameList={frame}
local beforePreview=resolves
for _,state in ipairs({"elite","rare","rareelite","worldboss"}) do
    assert(portrait.SetClassificationPreview("player",state))
    local expected=state=="elite" and gold or state=="worldboss" and winged or silver
    assert(dragon:IsShown() and dragon.atlas==expected,"runtime live sample "..state)
    portrait.Update(frame,"UNIT_CLASSIFICATION_CHANGED","player")
    assert(dragon:IsShown() and dragon.atlas==expected,"classification event retains runtime sample")
end
assert(resolves==beforePreview,"runtime selector does not resolve portrait image")
local driver
for _,region in ipairs(world.widgets.frames) do
    if region.events and region.events.PLAYER_REGEN_DISABLED and region:GetScript("OnEvent") then driver=region end
end
assert(driver,"runtime combat driver")
classification="rareelite"
driver:GetScript("OnEvent")(driver,"PLAYER_REGEN_DISABLED")
assert(not portrait.GetClassificationPreview("player") and dragon.atlas==silver,"combat restores actual identity")
assert(not driver.events.PLAYER_REGEN_DISABLED,"inactive preview has no combat subscription")
env.InCombatLockdown=function() return true end
assert(not portrait.SetClassificationPreview("player","elite"),"cannot enable runtime preview in combat")
env.InCombatLockdown=function() return false end
portrait.SetClassificationPreview("player","elite")
portrait.SetClassificationPreview("player","OFF")
assert(not portrait.GetClassificationPreview("player") and dragon.atlas==silver,"Off restores actual identity")
portrait.SetClassificationPreview("target","elite")
assert(dragon.atlas==silver,"another unit scope does not override player")
portrait.SetClassificationPreview(nil)
-- Build the actual portrait controls and exercise their ephemeral callbacks.
function Methods:SetChecked(value) self.checked=value and true or false end
function Methods:GetChecked() return self.checked end
function Methods:GetValue() return self.value or 0 end
local M=core.MSUF2
M.unitPortraitTabSelection={player="border"}
local ctx={key="uf_player",width=720,refreshers={}}
local binding, gateRefresh
local originalBind=M.BindDropdownWidget
M.BindDropdownWidget=function(c,widget,get,set,meta)
    if meta and meta.controlId and meta.controlId:find("classification_preview",1,true) then
        binding={widget=widget,get=get,set=set,meta=meta}
    end
    return originalBind(c,widget,get,set,meta)
end
local originalTrack=M.TrackCollapsibleRefresh
M.TrackCollapsibleRefresh=function(c,section,refresh)
    gateRefresh=refresh
    return originalTrack(c,section,refresh)
end
local sectionSpec
for _,spec in ipairs(M.UnitPage._sectionRegistry) do if spec.id=="portrait" then sectionSpec=spec end end
assert(sectionSpec,"portrait section registry")
local builder={}
function builder:CollapsibleSection(_,_,height)
    local section=env.CreateFrame("Frame",nil,env.UIParent)
    section:SetSize(720,height); section._msuf2Width=720
    return section
end
sectionSpec.build(ctx,builder,"player")
M.BindDropdownWidget=originalBind
M.TrackCollapsibleRefresh=originalTrack
assert(binding and binding.meta.classification=="ephemeral" and not binding.meta.settingKey,
    "runtime preview must not write a profile setting")
binding.set("elite")
assert(binding.get()=="elite" and dragon.atlas==gold,"menu runtime selection paints real frame")
binding.widget:GetScript("OnHide")(binding.widget)
assert(binding.get()=="OFF" and dragon.atlas==silver,"leaving preview control restores real identity")
binding.set("worldboss")
conf.portraitBlizzardElite=false; apply(); gateRefresh()
assert(binding.get()=="OFF" and not dragon:IsShown(),"disabling the feature clears runtime session")
conf.portraitBlizzardElite=true; apply(); gateRefresh()
binding.set("rare")
conf.portraitShape="CIRCLE"; apply(); gateRefresh()
assert(binding.get()=="OFF" and not dragon:IsShown(),"changing shape clears runtime session")
UF.frameList=priorFrameList
print("portrait_settings_smoke: OK ("..flavor..", including elite/rare dragons)")
