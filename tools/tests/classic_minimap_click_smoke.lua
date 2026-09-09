-- Exercise actual click registration, not just calling OnClick directly.
local root = arg[1] or "."
for _, flavor in ipairs({"Vanilla", "TBC", "Mists", "Mainline"}) do
 for _, broker in ipairs({false, true}) do
    local frames, object, toggles, opens, shifted = {}, nil, 0, 0, false
    local function frame(kind, name)
        local f = { scripts = {}, clicks = {LeftButtonUp=true} }
        function f:SetScript(k,v) self.scripts[k]=v end
        function f:RegisterForClicks(...) self.clicks={} for _,v in ipairs({...}) do self.clicks[v]=true end end
        function f:Click(button)
            if self.clicks[button.."Up"] then self.scripts.OnClick(self,button) end
        end
        function f:CreateTexture() return frame() end
        setmetatable(f,{__index=function() return function() end end})
        frames[#frames+1]=f
        if name then _G[name]=f end
        return f
    end
    _G.CreateFrame=frame
    _G.Minimap=frame()
    _G.MSUF_DB={general={showMinimapIcon=true}}
    _G.MSUF_EditState={active=false}
    _G.MSUF_NS={Client={Flavor=flavor}}
    _G.IsShiftKeyDown=function() return shifted end
    _G.MSUF_SetMSUFEditModeDirect=function(active)
        toggles=toggles+1;_G.MSUF_EditState.active=active
    end
    _G.MSUF_OpenStandaloneOptionsWindow=function(page)
        opens=opens+1;assert(page==(shifted and "profiles" or nil))
    end
    _G.LibStub=broker and function(lib)
        if lib=="LibDataBroker-1.1" then return {NewDataObject=function(_,_,data) object=data; return data end} end
        return {IsRegistered=function() return false end,Register=function() end,Show=function() end,Hide=function() end}
    end or nil
    assert(loadfile(root.."/MidnightSimpleUnitFrames/Shell/MSUF_MinimapButton.lua"))("MidnightSimpleUnitFrames",_G.MSUF_NS)
    local init=frames[#frames]
    init.scripts.OnEvent(init,"PLAYER_LOGIN")
    local click=broker and function(button) object.OnClick(nil,button) end
        or function(button) _G.MSUF_MinimapButton:Click(button) end
    click("RightButton")
    assert(toggles==1 and _G.MSUF_EditState.active, flavor.." right click must enter")
    click("RightButton")
    assert(toggles==2 and not _G.MSUF_EditState.active, flavor.." right click must exit")
    click("LeftButton");shifted=true;click("LeftButton")
    assert(opens==2 and toggles==2, "left/shift clicks must retain options/profile behavior")
 end
end
print("classic_minimap_click_smoke: OK (4 flavors, native fallback and LibDBIcon)")
