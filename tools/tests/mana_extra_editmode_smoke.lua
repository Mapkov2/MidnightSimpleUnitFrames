local root=assert(arg[1])
local World=assert(loadfile(root..'/tools/tests/client_world.lua'))()
for _,flavor in ipairs({'Mainline','Forever','Vanilla','TBC','Mists'}) do
    local world=World.New(root,flavor);world:Boot()
    assert(not world:FirstFailure(),flavor..': boot failed')
    local env,MSUF=world.env,world.core
    local combat,reads,newTimers=false,0,0
    env.InCombatLockdown=function() return combat end
    env.UnitPowerType=function() reads=reads+1;return 0 end
    env.UnitPower=function() reads=reads+1;return 100 end
    env.UnitPowerMax=function() reads=reads+1;return 100 end
    env.C_Timer.NewTimer=function() newTimers=newTimers+1;error('static samples scheduled timer') end
    -- The regeneration strips need the duration API; this fixture has it.
    env.C_DurationUtil=setmetatable({CreateDuration=function() return World.Stub end},{__index=World.Stub})
    local regen=flavor=='Forever' or flavor=='Vanilla' or flavor=='TBC'
    local host=env.CreateFrame('StatusBar',nil,env.UIParent)
    host:SetSize(240,14);host:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
    host._msufPowerType=0;host._msufPowerDisplayMana=false
    local player={targetPowerBar=host}
    local bars={manaRegenPause=true,manaGainPulse=true,manaUpcomingCost=true}
    local E={db={bars=bars},AM={visible=false},GetPlayerFrame=function() return player end,
        NotSecret=function() return true end}
    local helper=MSUF.CPBuilders.ManaExtras(E)
    helper.Refresh()
    local function shownSamples(parent)
        local shown={}
        for _,bar in ipairs(parent.children) do
            if bar.GetValue and bar:IsShown() then
                local value=bar:GetValue()
                if value==.18 or value==.5 or value==.6 then shown[#shown+1]=bar end
            end
        end
        return shown
    end
    env.MSUF_UnitEditModeActive=true
    local before=reads
    MSUF.EditModeAPI._BeginSession()
    helper.Refresh()
    assert(reads==before,flavor..': Edit refresh read mana')
    local samples=shownSamples(host)
    assert(#samples==(regen and 3 or 1),flavor..': feature-gated samples missing')
    local cost
    for _,bar in ipairs(samples) do if bar:GetValue()==.18 then cost=bar end end
    assert(cost and cost:GetStatusBarTexture():GetNumMaskTextures()==1,'cost clipping absent')
    local alt=env.CreateFrame('StatusBar',nil,env.UIParent)
    alt:SetSize(180,20);alt:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
    alt:SetOrientation('VERTICAL');alt:SetReverseFill(true)
    E.AM.visible=true;E.AM.bar=alt
    helper.Refresh()
    assert(reads==before,'alternate Edit refresh read mana')
    for _,bar in ipairs(samples) do assert(bar:IsShown() and bar:GetParent()==alt,'alternate mana samples missing') end
    assert(cost:GetParent()==alt and cost:GetOrientation()=='VERTICAL','host rebind wrong')
    alt._msufPowerShapeActive=true;alt._msufTexture='shape'
    helper.Refresh()
    assert(cost:GetStatusBarTexture():GetNumMaskTextures()==2,'shape sample mask absent')
    alt._msufPowerShapeActive=false;helper.Refresh()
    assert(cost:GetStatusBarTexture():GetNumMaskTextures()==1,'old shape sample mask retained')
    combat=true;env.MSUF_UnitEditModeActive=false
    MSUF.EditModeAPI._EndSession('save')
    for _,bar in ipairs(samples) do assert(not bar:IsShown(),'combat Edit exit left samples visible') end
    combat=false;helper.Refresh()
    env.MSUF_UnitEditModeActive=true;MSUF.EditModeAPI._BeginSession();helper.Refresh()
    helper.Disable()
    for _,bar in ipairs(samples) do assert(not bar:IsShown(),'disable left sample visible') end
    assert(cost:GetStatusBarTexture():GetNumMaskTextures()==0,'disable sample cleanup failed')
    assert(newTimers==0,'sample timer created')
    print('mana_extra_editmode_smoke '..flavor..': PASS')
end
