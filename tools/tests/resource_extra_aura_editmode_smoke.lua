local root = assert(arg[1])
local World = assert(loadfile(root .. '/tools/tests/client_world.lua'))()
for _, flavor in ipairs({'Mainline','Forever','Vanilla','TBC','Mists'}) do
    local world = World.New(root, flavor); world:Boot()
    assert(not world:FirstFailure(), flavor .. ': boot failed')
    local MSUF, env = world.core, world.env
    local count, combat, sensors = 0, false, {}
    env.InCombatLockdown = function() return combat end
    env.C_Secrets = {ShouldAurasBeSecret=function() return false end}
    env.MSUF_Auras3 = {CreateClassPowerAuraSensor=function(host)
        count=count+1
        local sensor={host=host,SetEnabled=function(self, enabled) self.enabled=enabled end}
        sensors[#sensors+1]=sensor; return sensor
    end}
    -- The client's spell data decides: only Midnight has the Arcane spells.
    env.C_Spell = setmetatable({DoesSpellExist=function(id) return flavor=='Mainline' and (id==365362 or id==451038) end},
        {__index=World.Stub})
    local bars = {showArcaneWindow=true,resourceExtraWidth=220,resourceExtraHeight=8,
        resourceExtraOffsetX=0,resourceExtraOffsetY=-18}
    local E = {db={bars=bars},PLAYER_CLASS='MAGE',GetSpec=function() return 1 end,
        GetPlayerFrame=function() return env.UIParent end,Texture=function() return 'texture' end,
        NotSecret=function() return true end}
    local helper = MSUF.CPBuilders.ExtraAuras(E)
    env.MSUF_EM2.State.IsActive=function() return env.MSUF_UnitEditModeActive==true end
    env.MSUF_EM2.State.GetProvider=function() return 'msuf' end
    env.MSUF_UnitEditModeActive = true
    MSUF.EditModeAPI._BeginSession()
    helper.Refresh()
    local key = 'external:msuf:resource-extras'
    local registry = env.MSUF_EM2.Registry
    local record = registry.Get(key)
    if flavor=='Mainline' then
        assert(record and record.isEnabled(), 'eligible extra mover missing')
        local frame = assert(record.getFrame()); assert(frame:IsShown())
        assert(frame:GetWidth()==220 and frame:GetHeight()==8, 'window sample dimensions wrong')
        -- One slot per phase (Arcane Surge, Arcane Soul) at one place.
        assert(count==2 and sensors[1].enabled and sensors[2].enabled, 'first activation in Edit did not prepare both live sensors')
        local external = env.MSUF_EM2.ExternalElements
        local captured = external.CaptureHistoryState(key)
        assert(captured.data.width==220 and captured.data.height==8, 'history dimensions absent')
        assert(external.ApplyMove(key,captured.data,23,-11,nil,nil,'preview'))
        assert(bars.resourceExtraOffsetX==23 and bars.resourceExtraOffsetY==-29, 'shared mover offsets wrong')
        local controls = external.GetControls(key)
        controls[1].set(300); controls[2].set(14)
        assert(frame:GetWidth()==300 and frame:GetHeight()==14, 'popup size controls not applied')
        for i = 1, 2 do
            assert(sensors[i].host:GetWidth()==300 and sensors[i].host:GetHeight()==14,
                'Edit resize left native host geometry stale')
            local _,_,_,x,y=sensors[i].host:GetPoint()
            assert(x==23 and y==-29, 'Edit drag did not update native host before combat')
        end
        assert(external.RestoreHistoryState(captured))
        assert(bars.resourceExtraWidth==220 and bars.resourceExtraHeight==8 and bars.resourceExtraOffsetX==0, 'history restore lost dimensions/offsets')
        bars.showArcaneWindow=false; helper.Refresh()
        assert(not frame:IsShown() and not record.isEnabled(), 'disabled sample or mover retained')
        bars.showArcaneWindow=true; helper.Refresh()
        assert(frame:IsShown())
        helper.Disable(); assert(not frame:IsShown() and not record.isEnabled(), 'helper teardown retained samples')
        assert(external.RestoreHistoryState(captured))
        assert(not frame:IsShown() and not record.isEnabled(), 'history restore re-enabled disabled helper')
        helper.Refresh()
        env.MSUF_UnitEditModeActive=false
        MSUF.EditModeAPI._EndSession('save')
        assert(not frame:IsShown() and count==2, 'Edit exit did not restore live native aura ownership')
        assert(sensors[1].enabled and sensors[2].enabled)
        env.MSUF_UnitEditModeActive=true; MSUF.EditModeAPI._BeginSession()
        assert(frame:IsShown() and sensors[1].enabled and sensors[2].enabled,
            'Edit entry disabled existing native aura sensors')
        controls[1].set(260); controls[2].set(12)
        combat=true;env.MSUF_UnitEditModeActive=false;MSUF.EditModeAPI._EndSession('save')
        assert(not frame:IsShown() and sensors[1].enabled and sensors[2].enabled,
            'combat exit stranded live aura sensors disabled')
        for i = 1, 2 do
            assert(sensors[i].host:GetWidth()==260 and sensors[i].host:GetHeight()==12,
                'direct combat transition lost freshly edited native geometry')
        end
        combat=false;helper.Refresh();helper.Disable()
        assert(not sensors[1].enabled and not sensors[2].enabled,'OOC disable did not release sensors')
    else
        assert(not record and count==0, flavor .. ': unsupported imported feature registered mover/sensors')
        MSUF.EditModeAPI._EndSession('save')
    end
    print(flavor .. ': extra aura mover/samples/history PASS')
end
