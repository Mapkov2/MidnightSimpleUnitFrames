local root=assert(arg[1]);local World=assert(loadfile(root..'/tools/tests/client_world.lua'))()
for _,flavor in ipairs({'Mainline','Forever','Vanilla','TBC','Mists'})do
 local world=World.New(root,flavor):Boot();local failure=world:FirstFailure();assert(not failure,failure and failure.message)
 local env,ns=world.env,world.core;env.MSUF_EnsureDB(true)
 local methods=world.widgets.Methods
 for _,key in ipairs({'SetStartPoint','SetEndPoint','SetThickness','SetAutoFocus','SetMaxLetters','EnableKeyboard'})do if not methods[key]then methods[key]=function()end end end
 env.C_Texture={GetAtlasInfo=function()return nil end}
 local Preview=assert(ns.UFPreview)
 local parent=env.CreateFrame('Frame',nil,env.UIParent);parent:SetSize(900,400)
 local panel=env.CreateFrame('Frame',nil,env.UIParent);local selected='player';panel._msufGetCurrentKey=function()return selected end
 local box=Preview._BuildPreview(parent,panel,900,400);box:Show();box.canvas:SetSize(400,200)
 local g=env.MSUF_DB.general;g.enablePlayerCastbar=true;g.castbarShowLatencyText=true;g.castbarShowChannelTicks=true;g.castbarAccentLastTick=true;g.showGCDBar=true;g.gcdBarDetached=true;g.gcdBarWidth=600;g.gcdBarHeight=50;g.gcdBarX=2000;g.gcdBarY=-2000
 ns.UF.Config.Refresh();Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES')
 local samples=assert(box.mock.cast._featureSamples,flavor..': no castbar samples')
 assert(samples.latency:IsShown() and samples.latency:GetText()=='50 ms')
 -- Five markers without an active channel, as the live player castbar draws; the last one is accented.
 assert(samples.ticks[5]:IsShown() and samples.ticks[5]:GetWidth()>samples.ticks[4]:GetWidth() and not samples.ticks[6])
 assert(samples.gcd:IsShown() and samples.gcd:GetWidth()+samples.gcd:GetHeight()+2<=400)
 local _,_,_,gx,gy=samples.gcd:GetPoint();assert(gx>=samples.gcd:GetHeight()+2 and gx+samples.gcd:GetWidth()<=400 and gy>=0 and gy+samples.gcd:GetHeight()<=200,'detached GCD or icon exceeded canvas')
 local cfg=env.MSUF_DB.player.castbar;cfg.channelTickUseCustom=true;cfg.channelTickCount=3;cfg.channelTickPosPct={80,20,50};Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES')
 assert(samples.ticks[1]:GetWidth()>samples.ticks[3]:GetWidth() and not samples.ticks[4]:IsShown())
 g.castbarShowLatencyText=false;g.castbarShowChannelTicks=false;g.showGCDBar=false;Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES')
 assert(not samples.latency:IsShown() and not samples.ticks[1]:IsShown() and not samples.gcd:IsShown())
 selected='target';g.enableTargetCastbar=true;g.kickReadyShowTarget=true;g.kickReadyTimeMarker=true;g.kickReadyTimeSegment=true;g.kickReadyColor={.2,.4,.8};Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES')
 assert(samples.kickMarker:IsShown() and samples.kickSegment:IsShown() and not samples.latency:IsShown())
 local color=samples.kickMarker.colorTexture;assert(color[1]==.2 and color[2]==.4 and color[3]==.8,'ready marker ignored runtime color table')
 g.kickReadyShowTarget=false;Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES');assert(not samples.kickMarker:IsShown() and not samples.kickSegment:IsShown())
 selected='player';g.showGCDBar=true;Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES');assert(samples.gcd:IsShown())
 selected='target';Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES');assert(not samples.gcd:IsShown(),'nonplayer scope retained detached GCD')
 selected='player';Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES');assert(samples.gcd:IsShown())
 box.layerVisibility=box.layerVisibility or {};box.layerVisibility.castbar=false;Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES');assert(not samples.gcd:IsShown(),'hidden cast layer retained detached GCD')
 print(flavor..': castbar feature preview painter PASS')
end
