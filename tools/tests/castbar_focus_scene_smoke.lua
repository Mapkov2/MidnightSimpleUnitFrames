-- Focus colors use the native secret selector and the runtime preview painter.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local SecretWorld = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()
local world = SecretWorld.New(root)
local core,env=world.core,world.env
core.Require('MSUF_EnsureDB','focus color scene smoke')()
local C,g=core.Castbars,env.MSUF_DB.general
g.castbarInterruptibleR,g.castbarInterruptibleG,g.castbarInterruptibleB=.2,.4,.8
g.castbarNonInterruptibleR,g.castbarNonInterruptibleG,g.castbarNonInterruptibleB=.9,.1,.1
g.focusCastbarOverrideEnabled=true
g.focusCastbarOverrideColor={.58,.52,1}
g.kickReadyShowFocus,g.kickReadyShowTarget=false,false
C.Backend.Set('focus','MSUF',g);C.Backend.Set('target','MSUF',g)
C.Config.Invalidate()
local focus=C.Driver.CastbarDriver_ApplyBackendState('focus')
local target=C.Driver.CastbarDriver_ApplyBackendState('target')
local function Color(c,r,green,b,why)
    local cr,cg,cb=c:GetRGB()
    assert(math.abs(cr-r)<.0001 and math.abs(cg-green)<.0001 and math.abs(cb-b)<.0001,why)
end
local raw=world.Secrets.New('boolean')
focus.isNotInterruptible=false;focus._msufApiNotInterruptibleRaw=raw
target.isNotInterruptible=false;target._msufApiNotInterruptibleRaw=raw
local stop=world:Watch({root..'/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua',
    root..'/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarDriver.lua'})
focus:UpdateColorForInterruptible();target:UpdateColorForInterruptible()
local ft,tt=focus.statusBar:GetStatusBarTexture(),target.statusBar:GetStatusBarTexture()
assert(rawequal(ft.vertexBoolean,raw),'secret interruptibility was replaced before native sink')
Color(ft.vertexIfFalse,.58,.52,1,'RED: focus native false branch not lavender')
Color(ft.vertexIfTrue,.9,.1,.1,'noninterruptible semantic branch changed')
Color(tt.vertexIfFalse,.2,.4,.8,'target changed with focus')
local make,count=env.CreateColor,0
env.CreateColor=function(...) count=count+1;return make(...) end
for i=1,100 do focus:UpdateColorForInterruptible();target:UpdateColorForInterruptible() end
env.CreateColor=make
assert(count==0,'alternating native paints allocated '..count..' colors')
local ready=world.Secrets.New('boolean')
local calls=world.counts.EvaluateColorFromBoolean
C.Utils.Castbar_ApplyNonInterruptibleTint(focus,raw,.9,.1,.1,1,.58,.52,1,1,false,
    .1,.7,.3,1,ready,true)
assert(world.counts.EvaluateColorFromBoolean>calls,'secret readiness bypassed native selector')
assert(rawequal(ft.vertexBoolean,raw) and world.Secrets.IsSecret(ft.vertexIfFalse.r),
    'secret readiness/interruptibility did not remain native')
local violations=stop()
assert(#violations==0,table.concat(violations,'\n'))
print('PASS strict secret native selection, preserved semantic branches, cache reuse')
local host=env.CreateFrame('Frame',nil,env.UIParent)
local sceneRoot=core.GF.NewPreviewScene(host);sceneRoot:Activate()
local sample={name='Test',duration=2,progress=.5,notInterruptible=false,kickReady=true}
local scene=sceneRoot:Castbar('focus',{sample=sample})
local sf=scene:Frame();local st=sf.statusBar:GetStatusBarTexture()
Color(st.vertexIfFalse,.58,.52,1,'RED: actual scene ignored focus override')
sample.notInterruptible=true;scene:SetOptions({sample=sample})
assert(st.vertexBoolean==true,'preview ignored noninterruptible sample')
Color(st.vertexIfTrue,.9,.1,.1,'preview changed noninterruptible palette')
sample.notInterruptible=false;g.focusCastbarOverrideEnabled=false
C.Config.Invalidate();scene:SetOptions({sample=sample})
Color(st.vertexIfFalse,.2,.4,.8,'preview toggle did not restore shared palette')
g.focusCastbarOverrideEnabled=true;g.focusCastbarOverrideColor={r=.17,g=.29,b=.43}
C.Config.Invalidate();scene:Refresh()
Color(st.vertexIfFalse,.17,.29,.43,'named RGB table differs in preview')
print('PASS actual native scene: focus enabled/disabled, warning, changed profile and named RGB')
do
    local final
    local native=st.SetVertexColorFromBoolean
    function st:SetVertexColorFromBoolean(value,yes,no)
        final={ (value and yes or no):GetRGBA() }
        return native(self,value,yes,no)
    end
    local plain=sf.statusBar.SetStatusBarColor
    function sf.statusBar:SetStatusBarColor(r,green,b,a)
        final={r,green,b,a};return plain(self,r,green,b,a)
    end
    local function SampleColor(r,green,b,label)
        C.Config.Invalidate();scene:SetOptions({sample=sample})
        assert(final and math.abs(final[1]-r)<.0001 and math.abs(final[2]-green)<.0001
            and math.abs(final[3]-b)<.0001,label)
    end
    g.kickReadyStyle='fill';g.kickReadyShowFocus=true;sample.kickReady=true
    g.castbarInterruptUnavailableR,g.castbarInterruptUnavailableG,g.castbarInterruptUnavailableB=.1,.7,.3
    SampleColor(.17,.29,.43,'RED: kick-ready scene overwrites focus override with indicator green')
    sample.kickReady=false
    SampleColor(.1,.7,.3,'RED: kick-unavailable scene ignored semantic unavailable fill')
    sample.notInterruptible=true
    SampleColor(.9,.1,.1,'noninterruptible focus sample must override readiness')
    print('PASS focus kick-fill preview: ready/custom, unavailable/global, noninterruptible/global')
end
sceneRoot:Deactivate()
