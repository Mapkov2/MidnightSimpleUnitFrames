-- Unit-frame drags preserve the visible cursor contract across anchor resolution,
-- runtime refresh, snapping and UI/frame scale changes. Real Forever load graph.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Forever")
local env, core = world.env, world.core
env.MAX_BOSS_FRAMES = 5
env.TotemFrame = false
env.UnitClass = function() return "Hunter", "HUNTER", 3 end
env.UnitExists = function() return true end
env.UnitIsConnected = function() return true end
env.UnitHealth = function() return 800 end
env.UnitHealthMax = function() return 1000 end
env.UnitHealthPercent = function() return 80 end
env.UnitPower = function() return 50 end
env.UnitPowerMax = function() return 100 end
env.UnitPowerPercent = function() return 50 end
env.UnitLevel = function() return 60 end
env.AbbreviateLargeNumbers = tostring
env.AbbreviateNumbers = tostring
env.BreakUpLargeNumbers = tostring
env.GetPhysicalScreenSize = function() return 2560, 1440 end
env.C_PetInfo = { GetPetHappiness = function() return 3, 1.25, 0 end }
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local function Public(name)
    return core.PublicGlobals and core.PublicGlobals[name] or env[name]
end
-- The generic boot fixture treats unknown native globals as callable tables.
-- Unit-frame names use the full addon prefix, so mark their absence explicitly.
for _, unit in ipairs(core.UF.unitOrder) do env[core.UF.FrameName(unit)] = false end
Public("MSUF_InitProfiles")()
local db = env.MSUF_DB
db.general.anchorToCooldown, db.general.anchorName = false, "UIParent"
db.general.msufUiScale, db.general.editModeSnapEnabled = 1, false
db.general.UIScale = { Enabled = false, Scale = 1 }
local ui = env.UIParent
ui.width, ui.height, ui.scale = 1366, 768, 1
ui.left, ui.bottom = 0, 0
ui.GetWidth=function(self) return 1366/self:GetScale() end
ui.GetHeight=function(self) return 768/self:GetScale() end
ui.GetLeft=function() return 0 end
ui.GetBottom=function() return 0 end
ui.GetRight=function(self) return self:GetWidth() end
ui.GetTop=function(self) return self:GetHeight() end
ui.GetCenter=function(self) return self:GetWidth()/2,self:GetHeight()/2 end
local UNIT_KEYS = { 'player', 'target', 'focus', 'pet', 'pettarget', 'targettarget', 'focustarget', 'boss' }
for _,key in ipairs(UNIT_KEYS) do
 local settings=db[key]
 settings.enabled,settings.width,settings.height=true,220,30
 settings.offsetX,settings.offsetY=-200,-80
 settings.anchorToUnitframe,settings.anchorFrameName='GLOBAL',nil
 settings.screenPositionMode=nil
end
local conf = db.pet
core.UF.Factory.SpawnAll()
local frame = assert(core.UF.frames.pet)
local EM2 = core.EditModeController or Public("MSUF_EM2")
local POINTS = { CENTER = { .5, .5 }, TOP = { .5, 1 }, BOTTOM = { .5, 0 }, LEFT = { 0, .5 }, RIGHT = { 1, .5 },
    TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { 0, 0 }, BOTTOMRIGHT = { 1, 0 } }

-- Model the native distinction: raw anchor points remain unchanged while a
-- clamped frame reports its actual visible rectangle in its own scale units.
local function NativeCenter(self)
    if type(self.allPoints) == "table" then
        local target = self.allPoints
        local x, y = target:GetCenter()
        if x==nil or y==nil then return nil,nil end
        local factor = target:GetEffectiveScale() / self:GetEffectiveScale()
        return x * factor, y * factor
    end
    local point, anchor, relativePoint, x, y = self:GetPoint()
    if not point then return 0, 0 end
    anchor = anchor or self:GetParent()
    local own, relative = assert(POINTS[point]), assert(POINTS[relativePoint])
    local scale, anchorScale = self:GetEffectiveScale(), anchor:GetEffectiveScale()
    local left,bottom=anchor:GetLeft(),anchor:GetBottom()
    if left==nil or bottom==nil then return nil,nil end
    local ax = left + anchor:GetWidth() * relative[1]
    local ay = bottom + anchor:GetHeight() * relative[2]
    local cx = ax * anchorScale / scale + (x or 0) + (.5 - own[1]) * self:GetWidth()
    local cy = ay * anchorScale / scale + (y or 0) + (.5 - own[2]) * self:GetHeight()
    if self.clampedToScreen then
        local halfW, halfH = self:GetWidth() / 2, self:GetHeight() / 2
        local screenW, screenH = ui:GetWidth() * ui:GetEffectiveScale() / scale, ui:GetHeight() * ui:GetEffectiveScale() / scale
        cx = math.max(halfW, math.min(screenW - halfW, cx))
        cy = math.max(halfH, math.min(screenH - halfH, cy))
    end
    return cx, cy
end
local function NativeGeometry(region)
    region.GetCenter = NativeCenter
    region.GetWidth = function(self)
        local target = self.allPoints
        if type(target) == "table" then return target:GetWidth() * target:GetEffectiveScale() / self:GetEffectiveScale() end
        return self.width
    end
    region.GetHeight = function(self)
        local target = self.allPoints
        if type(target) == "table" then return target:GetHeight() * target:GetEffectiveScale() / self:GetEffectiveScale() end
        return self.height
    end
    region.GetLeft = function(self) local x=self:GetCenter(); return x and x-self:GetWidth()/2 end
    region.GetRight = function(self) local x=self:GetCenter(); return x and x+self:GetWidth()/2 end
    region.GetBottom = function(self) local _,y=self:GetCenter(); return y and y-self:GetHeight()/2 end
    region.GetTop = function(self) local _,y=self:GetCenter(); return y and y+self:GetHeight()/2 end
end
NativeGeometry(frame)
local function CenterUI(region)
    local x, y = region:GetCenter()
    if x==nil or y==nil then return nil,nil end
    local factor = region:GetEffectiveScale() / ui:GetEffectiveScale()
    return x * factor, y * factor
end
local function RootBounds()
    local x, y = CenterUI(frame)
    local factor = frame:GetEffectiveScale() / ui:GetEffectiveScale()
    local halfW, halfH = frame:GetWidth() * factor / 2, frame:GetHeight() * factor / 2
    return x - halfW, x + halfW, y + halfH, y - halfH
end

local function UnitToken(key) return key == "boss" and "boss1" or key end
for _,key in ipairs(UNIT_KEYS) do
    local button=assert(core.UF.frames[UnitToken(key)], key .. " frame missing")
    NativeGeometry(button)
    local registry=assert(EM2.Registry.Get(key), key .. " mover registry missing")
    registry.getMoverBounds=function()
        local x,y=CenterUI(button)
        if x==nil or y==nil then return nil end
        local factor=button:GetEffectiveScale()/ui:GetEffectiveScale()
        return x-button:GetWidth()*factor/2,x+button:GetWidth()*factor/2,
            y+button:GetHeight()*factor/2,y-button:GetHeight()*factor/2
    end
end
for index=2,5 do NativeGeometry(assert(core.UF.frames["boss"..index])) end
assert(EM2.State.Enter("player"))
world.widgets:RunTimers()
for _,key in ipairs(UNIT_KEYS) do NativeGeometry(assert(EM2.Movers.Get(key), key .. " mover missing")) end
local cursorX,cursorY,mouseDown=0,0,true
env.GetCursorPosition=function() return cursorX,cursorY end
env.IsMouseButtonDown=function() return mouseDown end
local ticker
for _,candidate in ipairs(world.widgets.frames) do
    if candidate.frameName=="MSUF_EM2_TickerFrame" then ticker=candidate end
end
assert(ticker,"ticker missing")
local failures,checks={},0
local function Check(ok,message)
    checks=checks+1
    if not ok then failures[#failures+1]=message end
end
local function Near(a,b) return math.abs(a-b)<=1.2 end
local function Physical(region)
    local x,y=region:GetCenter()
    local scale=region:GetEffectiveScale()
    return x and x*scale or math.huge,y and y*scale or math.huge
end
local external=env.CreateFrame("Frame","MovementGlobalAnchor",ui)
external:SetSize(300,100)
external:SetPoint("CENTER",ui,"CENTER",280,120)
NativeGeometry(external)
env.MovementGlobalAnchor=external
local rectless=env.CreateFrame("Frame","MovementRectlessAnchor",ui)
for _,method in ipairs({"GetCenter","GetLeft","GetRight","GetTop","GetBottom"}) do
    rectless[method]=function() return nil,nil end
end
local cases={}
for index,key in ipairs(UNIT_KEYS) do
    cases[#cases+1]={name=key .. " preset snap/runtime refresh",key=key,snap=true,
        uiScale=index%2==0 and .8 or 1,frameScale=index%3==0 and 1.25 or (index%3==1 and .8 or 1)}
end
for _,key in ipairs({"player","target","focus","pet","pettarget","targettarget","focustarget"}) do
    cases[#cases+1]={name=key .. " explicit UIParent under global custom anchor",key=key,explicitUI=true}
end
cases[#cases+1]={name="UI scale changes during ordinary drag",key="pet",changeUI=.8}
cases[#cases+1]={name="frame scale changes during ordinary drag",key="player",changeFrame=1.25}
cases[#cases+1]={name="both scales change with non-center points",key="target",changeUI=.8,changeFrame=1.25,
    point="RIGHT",relativePoint="CENTER"}
cases[#cases+1]={name="boss stack changes scale during drag",key="boss",changeUI=.8,changeFrame=1.25}
cases[#cases+1]={name="moving custom anchor during drag",key="pet",movingAnchor=true}
cases[#cases+1]={name="legacy UI_Parent alias",key="focus",explicitUI=true,alias=true}
cases[#cases+1]={name="hidden geometric custom provider",key="pet",hiddenAnchor=true}
cases[#cases+1]={name="missing provider cached position",key="pet",missingAnchor=true}
cases[#cases+1]={name="Essential cooldown edge margins",key="player",cooldown=true}
cases[#cases+1]={name="rectless replacement provider",key="pet",rectlessAnchor=true}
cases[#cases+1]={name="sparse legacy x/y offsets",key="focus",sparse=true}
cases[#cases+1]={name="provider disappears mid-drag",key="pet",movingAnchor=true,disappears=true}
cases[#cases+1]={name="provider loses geometry mid-drag",key="pet",movingAnchor=true,losesGeometry=true}
cases[#cases+1]={name="provider recovers geometry mid-drag",key="pet",movingAnchor=true,losesGeometry=true,recovers=true}
cases[#cases+1]={name="held missing-anchor drag Stop(true)",key="pet",missingAnchor=true,stopHeld=true}
for _,case in ipairs(cases) do
    local key=case.key
    NativeGeometry(external)
    env.MovementGlobalAnchor=external
    env.EssentialCooldownViewer=case.cooldown and external or false
    external:ClearAllPoints()
    external:SetPoint("CENTER",ui,"CENTER",280,120)
    external:SetShown(not case.hiddenAnchor)
    conf=db[key]
    frame=core.UF.frames[UnitToken(key)]
    ui:SetScale(case.uiScale or 1)
    for _,token in ipairs(key=="boss" and {"boss1","boss2","boss3","boss4","boss5"} or {key}) do
        core.UF.frames[token]:SetScale(case.frameScale or 1)
    end
    db.general.anchorToCooldown=false
    db.general.anchorName=case.explicitUI and "MovementGlobalAnchor" or "UIParent"
    db.general.editModeSnapEnabled=case.snap==true
    db.general.editModeGridEnabled=true
    db.general.editModeGridStep=36
    db.general.editModeSnapModeGrid=true
    db.general.editModeSnapMode="grid"
    db.general.editModeSnapToGrid=false
    conf.point,conf.relativePoint=case.point or "CENTER",case.relativePoint or "CENTER"
    conf.anchorFrameName=case.explicitUI and (case.alias and "UI_Parent" or "UIParent")
        or (case.cooldown and "EssentialCooldownViewer")
        or ((case.movingAnchor or case.hiddenAnchor or case.missingAnchor or case.rectlessAnchor) and "MovementGlobalAnchor" or nil)
    conf.anchorToUnitframe="GLOBAL"
    conf.offsetX,conf.offsetY=-200,-80
    conf.x,conf.y=nil,nil
    if case.sparse then conf.x,conf.y=-200,-80; conf.offsetX,conf.offsetY=nil,nil end
    conf.screenPositionMode=nil
    for _,token in ipairs(core.UF.UnitsForConfigKey(key)) do core.UF.Config.RefreshUnit(token) end
    core.UF.Factory.ForceReanchor(key)
    local _,nativeAnchor=frame:GetPoint()
    if nativeAnchor and nativeAnchor._msufUnitExternalAnchorProxy==true then
        NativeGeometry(nativeAnchor)
        core.UF.Factory.ForceReanchor(key)
    end
    if case.rectlessAnchor then
        env.MovementGlobalAnchor=rectless
        core.UF.Factory.ForceReanchor(key)
    end
    if case.missingAnchor then
        Public("MSUF_CacheUnitFrameScreenPosition")(frame,key,UnitToken(key),conf.point)
        env.MovementGlobalAnchor=false
        core.UF.Factory.ForceReanchor(key)
        Check(frame._msufLoadedFromScreenCache==true,case.name .. ": missing provider did not restore its saved screen position")
    end
    EM2.Movers.SyncKey(key)
    local mover=EM2.Movers.Get(key)
    cursorX,cursorY=Physical(mover)
    mouseDown=true
    Check(mover:GetScript("OnMouseDown")(mover,"LeftButton")==true,case.name .. ": drag rejected")
    mover:GetScript("OnDragStart")(mover,"LeftButton")
    local firstX,firstY=Physical(frame)
    local stack={}
    if key=="boss" then
        for index=1,5 do local x,y=Physical(core.UF.frames["boss"..index]);stack[index]={x,y} end
    end
    for step=1,3 do
        if step==3 and case.recovers then NativeGeometry(external) end
        if step==2 then
            if case.disappears then env.MovementGlobalAnchor=false end
            if case.losesGeometry then
                for _,method in ipairs({"GetCenter","GetLeft","GetRight","GetTop","GetBottom"}) do
                    external[method]=rectless[method]
                end
            end
            if case.movingAnchor then
                external:ClearAllPoints()
                external:SetPoint("CENTER",ui,"CENTER",330,120)
            end
            if case.changeUI then ui:SetScale(case.changeUI) end
            if case.changeFrame then
                for _,token in ipairs(core.UF.UnitsForConfigKey(key)) do core.UF.frames[token]:SetScale(case.changeFrame) end
            end
        end
        cursorX,cursorY=cursorX+(case.movingAnchor and step==2 and 10 or 40),cursorY+20
        local expectedX,expectedY=cursorX/ui:GetEffectiveScale(),cursorY/ui:GetEffectiveScale()
        if case.snap then
            local factor=mover:GetEffectiveScale()/ui:GetEffectiveScale()
            expectedX,expectedY=EM2.Snap.Apply(expectedX,expectedY,mover:GetWidth()*factor/2,mover:GetHeight()*factor/2,key)
        end
        expectedX,expectedY=expectedX*ui:GetEffectiveScale(),expectedY*ui:GetEffectiveScale()
        local update=ticker:GetScript("OnUpdate")
        if update then update(ticker,.016) end
        local actualX,actualY=Physical(frame)
        Check(Near(actualX,expectedX) and Near(actualY,expectedY),case.name .. ": tick "..step.." lost cursor placement")
        for _,token in ipairs(core.UF.UnitsForConfigKey(key)) do core.UF.Config.RefreshUnit(token) end
        core.UF.Factory.Apply(key)
        local refreshedX,refreshedY=Physical(frame)
        Check(Near(actualX,refreshedX) and Near(actualY,refreshedY),case.name .. ": runtime refresh moved the active drag")
        if key=="boss" and not (case.changeUI or case.changeFrame) then
            for index=2,5 do
                local x,y=Physical(core.UF.frames["boss"..index])
                Check(Near(x-stack[index][1],actualX-firstX) and Near(y-stack[index][2],actualY-firstY),
                    case.name .. ": boss "..index.." did not move with its stack")
            end
        end
    end
    local lastX,lastY=Physical(frame)
    -- Release outside the mover: the driver owns the fallback mouse-up.
    if case.stopHeld then
        EM2.Ticker.Stop(true)
        for _,token in ipairs(core.UF.UnitsForConfigKey(key)) do core.UF.Config.RefreshUnit(token) end
        core.UF.Factory.Apply(key)
        EM2.Movers.SyncKey(key)
    end
    mouseDown=false
    local update=ticker:GetScript("OnUpdate")
    if update then update(ticker,.016) end
    Check(not EM2.Ticker.IsDragging() and (case.stopHeld or mover._dragging==false),case.name .. ": outside release left drag active")
    world.widgets:RunTimers()
    local finalX,finalY=Physical(frame)
    Check(Near(lastX,finalX) and Near(lastY,finalY),case.name .. ": release snapped the frame back "
        ..string.format("(%.1f, %.1f -> %.1f, %.1f)",lastX,lastY,finalX,finalY))
    local mx,my=Physical(mover)
    Check(Near(mx,finalX) and Near(my,finalY),case.name .. ": final mover detached from frame")
    core.UF.Factory.ForceReanchor(key)
    local replayX,replayY=Physical(frame)
    Check(Near(lastX,replayX) and Near(lastY,replayY),case.name .. ": later runtime apply lost the saved drag position")
    if case.stopHeld then
        mover:GetScript("OnMouseUp")(mover,"LeftButton")
        EM2.Ticker.Start()
    end
end

-- A mouse-down starts the ticker before native OnDragStart. Snapping must not
-- move a frame for an ordinary stationary click merely near another mover.
ui:SetScale(1)
frame,conf=core.UF.frames.pet,db.pet
frame:SetScale(1)
db.general.anchorName="UIParent"
db.general.editModeSnapEnabled=true
db.general.editModeGridEnabled,db.general.editModeGridStep=true,36
db.general.editModeSnapMode,db.general.editModeSnapModeGrid="grid",true
db.general.editModeSnapToGrid=false
conf.point,conf.relativePoint,conf.anchorToUnitframe="CENTER","CENTER","GLOBAL"
conf.anchorFrameName,conf.screenPositionMode=nil,nil
conf.offsetX,conf.offsetY=-200,-80
core.UF.Config.RefreshUnit("pet")
core.UF.Factory.ForceReanchor("pet")
EM2.Movers.SyncKey("pet")
local neighbour=db.target
neighbour.point,neighbour.relativePoint,neighbour.anchorToUnitframe="CENTER","CENTER","GLOBAL"
neighbour.anchorFrameName,neighbour.screenPositionMode=nil,nil
neighbour.offsetX,neighbour.offsetY=-195,-80
core.UF.frames.target:SetScale(1)
core.UF.Config.RefreshUnit("target")
core.UF.Factory.ForceReanchor("target")
EM2.Movers.SyncKey("target")
local mover=EM2.Movers.Get("pet")
local stationaryX,stationaryY=Physical(frame)
local offsetX,offsetY=conf.offsetX,conf.offsetY
cursorX,cursorY=Physical(mover)
mouseDown=true
Check(mover:GetScript("OnMouseDown")(mover,"LeftButton")==true,"stationary snapped click rejected")
ticker:GetScript("OnUpdate")(ticker,.016)
local clickedX,clickedY=Physical(frame)
Check(Near(clickedX,stationaryX) and Near(clickedY,stationaryY),"stationary click snapped the visible frame without cursor movement")
Check(conf.offsetX==offsetX and conf.offsetY==offsetY,"stationary click rewrote the saved position while snapping")
local moved=mover:GetScript("OnMouseUp")(mover,"LeftButton")
Check(moved==false,"stationary click committed a drag")
world.widgets:RunTimers()
local afterX,afterY=Physical(frame)
Check(Near(afterX,stationaryX) and Near(afterY,stationaryY),"stationary click retained an unsolicited position change")
assert(#failures==0,"unitframe_editmode_movement_smoke failed:\n"..table.concat(failures,"\n"))
print("unitframe_editmode_movement_smoke: PASS ("..checks.." checks)")
