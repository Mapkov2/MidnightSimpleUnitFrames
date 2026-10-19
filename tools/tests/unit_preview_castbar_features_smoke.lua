-- unit_preview_castbar_features_smoke.lua <repoRoot>
--
-- The Unit preview's castbar slot paints the engine castbar scene, so the latency text, the channel markers and
-- the Interrupt Ready time marker are the live castbar's own regions. The detached GCD bar is not part of the
-- castbar and stays a small preview strip on the slot. Five clients, one world each.
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
 local function Refresh()ns.UF.Config.Refresh();ns.Castbars.Config.Refresh();Preview.Refresh(box,'CASTBAR_FEATURE_SAMPLES')end
 local function Frame()local scene=assert(box._castScene,flavor..': no castbar scene');return assert(scene:Frame(),flavor..': the castbar scene painted no frame')end
 Refresh()
 local frame=Frame();local samples=assert(box.mock.cast._featureSamples,flavor..': no castbar samples')
 assert(frame.latencyText:IsShown() and frame.latencyText:GetText()=='50 ms',flavor..': latency text missing')
 -- Five markers without an active channel, as the live player castbar draws; the draining channel's fill edge
 -- reaches the nearest marker last, so that one is accented.
 local ticks=frame._msufPlayerChannelHasteMarkers
 assert(ticks[5]:IsShown() and ticks[1]:GetWidth()>ticks[2]:GetWidth() and not (ticks[6] and ticks[6]:IsShown()),flavor..': channel markers')
 assert(samples.gcd:IsShown() and samples.gcd:GetWidth()+samples.gcd:GetHeight()+2<=400)
 local _,_,_,gx,gy=samples.gcd:GetPoint();assert(gx>=samples.gcd:GetHeight()+2 and gx+samples.gcd:GetWidth()<=400 and gy>=0 and gy+samples.gcd:GetHeight()<=200,'detached GCD or icon exceeded canvas')
 local cfg=env.MSUF_DB.player.castbar;cfg.channelTickUseCustom=true;cfg.channelTickCount=3;cfg.channelTickPosPct={80,20,50};Refresh()
 ticks=Frame()._msufPlayerChannelHasteMarkers
 assert(ticks[2]:GetWidth()>ticks[3]:GetWidth() and ticks[2]:GetWidth()>ticks[1]:GetWidth() and not (ticks[4] and ticks[4]:IsShown()),flavor..': custom channel markers')
 g.castbarShowLatencyText=false;g.castbarShowChannelTicks=false;g.showGCDBar=false;Refresh()
 frame=Frame()
 assert(not frame.latencyText:IsShown() and not ticks[1]:IsShown() and not samples.gcd:IsShown(),flavor..': samples stayed after their switches went off')
 selected='target';g.enableTargetCastbar=true;g.kickReadyShowTarget=true;g.kickReadyTimeMarker=true;g.kickReadyTimeSegment=true;g.kickReadyColor={.2,.4,.8};Refresh()
 frame=Frame();local projection=assert(frame._msufKickTimeProjections and frame._msufKickTimeProjections[1],flavor..': no Interrupt Ready projection')
 assert(projection.marker:IsShown() and projection.segment:IsShown() and not (frame.latencyText and frame.latencyText:IsShown()),flavor..': time marker and segment')
 local color=projection.marker.colorTexture;assert(color[1]==.2 and color[2]==.4 and color[3]==.8,'ready marker ignored runtime color table')
 g.kickReadyShowTarget=false;Refresh();frame=Frame()
 assert(not projection.marker:IsShown() and not projection.segment:IsShown(),flavor..': time marker stayed with Interrupt Ready off')
 selected='player';g.showGCDBar=true;Refresh();assert(samples.gcd:IsShown())
 selected='target';Refresh();assert(not samples.gcd:IsShown(),'nonplayer scope retained detached GCD')
 selected='player';Refresh();assert(samples.gcd:IsShown())
 box.layerVisibility=box.layerVisibility or {};box.layerVisibility.castbar=false;Refresh();assert(not samples.gcd:IsShown(),'hidden cast layer retained detached GCD')
 assert(not box.mock.cast:IsShown() and box._castScene:Frame()==nil,flavor..': hidden cast layer kept the castbar scene')
 print(flavor..': castbar feature preview painter PASS')
end
