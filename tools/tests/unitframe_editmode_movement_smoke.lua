-- Unit-frame drags preserve the visible cursor contract across anchor resolution,
-- runtime refresh, snapping and UI/frame scale changes. Real Mainline/Forever load graphs.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, arg[2] or "Forever")
local env, core = world.env, world.core
local inRaid = false
env.IsInRaid = function() return inRaid end
env.IsInGroup = function() return inRaid end
env.GetNumGroupMembers = function() return inRaid and 10 or 0 end
env.GetRaidRosterInfo = function(index)
    if not inRaid or index > 10 then return nil end
    return "Member" .. index, 0, math.floor((index - 1) / 5) + 1, 60, "WARRIOR", "WARRIOR", "zone", true, false, nil, nil, "DAMAGER"
end
-- Native EditBoxes fire focus loss synchronously when ClearFocus is called.
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets",
    "SetMaxLetters", "SetCursorPosition", "HighlightText", "SetAutoFocus" }) do
    world.widgets.Methods[name] = function() end
end
world.widgets.Methods.HasFocus = function(self) return self.focused == true end
world.widgets.Methods.ClearFocus = function(self)
    local focused = self.focused
    self.focused = false
    local callback = self:GetScript("OnEditFocusLost")
    if focused and callback then callback(self) end
end
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
local replacement=env.CreateFrame("Frame","MovementReplacementAnchor",ui)
replacement:SetSize(300,100)
replacement:SetPoint("CENTER",ui,"CENTER",280,330)
NativeGeometry(replacement)
local cases={}
for _,key in ipairs(UNIT_KEYS) do
    cases[#cases+1]={name=key.." provider returns after release",key=key,movingAnchor=true,vanishAtRelease=true,returnAfterRelease=true}
    for _,transition in ipairs({"recoverAtRelease","replaceAtRelease","moveAtRelease","loseAtRelease"}) do
        local case={name=key.." held stop "..transition,key=key,stopHeld=true}
        case[transition]=true
        case.missingAnchor=transition=="recoverAtRelease"
        case.movingAnchor=not case.missingAnchor
        cases[#cases+1]=case
    end
end
for _,key in ipairs(UNIT_KEYS) do
    cases[#cases+1]={name=key.." missing anchor recovers at release",key=key,missingAnchor=true,recoverAtRelease=true}
    cases[#cases+1]={name=key.." anchor replaced at release",key=key,movingAnchor=true,replaceAtRelease=true}
    cases[#cases+1]={name=key.." anchor moves after last tick",key=key,movingAnchor=true,moveAtRelease=true}
    cases[#cases+1]={name=key.." anchor loses rect after last tick",key=key,movingAnchor=true,loseAtRelease=true}
end
for _,key in ipairs(UNIT_KEYS) do
    for _,transition in ipairs({"recoverAtRelease","replaceAtRelease","moveAtRelease","loseAtRelease"}) do
        local case={name=key.." external shell "..transition,key=key,externalShell=true}
        case[transition]=true
        case.missingAnchor=transition=="recoverAtRelease"
        case.movingAnchor=not case.missingAnchor
        cases[#cases+1]=case
    end
end
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
for _,key in ipairs(UNIT_KEYS) do
    cases[#cases+1]={name=key.." cooldown provider replaced at release",key=key,cooldown=true,replaceAtRelease=true}
end
cases[#cases+1]={name="scaled corner anchor replaced",key="player",movingAnchor=true,replaceAtRelease=true,
    uiScale=.8,frameScale=1.25,point="BOTTOMRIGHT",relativePoint="TOPLEFT"}
cases[#cases+1]={name="scaled rectless anchor at release",key="pet",movingAnchor=true,loseAtRelease=true,
    uiScale=.8,frameScale=.8,point="RIGHT",relativePoint="BOTTOMLEFT"}
cases[#cases+1]={name="compiled anchor points change at release",key="focus",movingAnchor=true,pointsAtRelease=true}
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
    local externalDrag
    if case.externalShell then
        externalDrag=EM2.Ticker.BeginExternalDrag(mover,key,EM2.Registry.Get(key))
        Check(externalDrag~=nil,case.name .. ": external drag rejected")
    else
        Check(mover:GetScript("OnMouseDown")(mover,"LeftButton")==true,case.name .. ": drag rejected")
        mover:GetScript("OnDragStart")(mover,"LeftButton")
    end
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
        if externalDrag then
            mover:ClearAllPoints()
            mover:SetPoint("CENTER",ui,"BOTTOMLEFT",expectedX/ui:GetEffectiveScale(),expectedY/ui:GetEffectiveScale())
            Check(EM2.Ticker.ApplyExternalDrag(externalDrag),case.name .. ": external tick rejected")
        elseif update then update(ticker,.016) end
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
    if case.vanishAtRelease then env.MovementGlobalAnchor=false end
    if case.recoverAtRelease then env.MovementGlobalAnchor=external end
    if case.replaceAtRelease then
        if case.cooldown then env.EssentialCooldownViewer=replacement else env.MovementGlobalAnchor=replacement end
    end
    if case.pointsAtRelease then conf.point,conf.relativePoint="TOPRIGHT","BOTTOMLEFT" end
    if case.moveAtRelease then
        external:ClearAllPoints()
        external:SetPoint("CENTER",ui,"CENTER",330,330)
    end
    if case.loseAtRelease then
        for _,method in ipairs({"GetCenter","GetLeft","GetRight","GetTop","GetBottom"}) do
            external[method]=rectless[method]
        end
    end
    -- Release outside the mover: the driver owns the fallback mouse-up.
    if externalDrag then
        EM2.Ticker.EndExternalDrag(externalDrag,true)
        for _,token in ipairs(core.UF.UnitsForConfigKey(key)) do core.UF.Config.RefreshUnit(token) end
        core.UF.Factory.Apply(key)
        EM2.Movers.SyncKey(key)
    end
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
    if case.returnAfterRelease then
        env.MovementGlobalAnchor=external
        core.UF.Factory.ForceReanchor(key)
        local returnedX,returnedY=Physical(frame)
        Check(Near(lastX,returnedX) and Near(lastY,returnedY),case.name .. ": provider return reinterpreted saved offsets")
    end
    for _,token in ipairs(core.UF.UnitsForConfigKey(key)) do
        Check(core.UF.frames[token]._msufDragActive~=true,case.name .. ": final apply left drag ownership active")
    end
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
-- A stationary external-shell click has no final position to persist.
local stationaryDrag=assert(EM2.Ticker.BeginExternalDrag(mover,"pet",EM2.Registry.Get("pet")))
Check(EM2.Ticker.EndExternalDrag(stationaryDrag,true)==false,"stationary external click committed a drag")
Check(conf.offsetX==offsetX and conf.offsetY==offsetY,"stationary external click rewrote saved offsets")
-- The event-derived combat edge precedes native lockdown. No close path may
-- perform the new final SetPoint while that configuration guard is active.
db.general.editModeSnapEnabled=false
for _,method in ipairs({"mouse","stop","external"}) do
    EM2.Movers.SyncKey("pet")
    cursorX,cursorY=Physical(mover)
    mouseDown=true
    local drag
    if method=="external" then
        drag=assert(EM2.Ticker.BeginExternalDrag(mover,"pet",EM2.Registry.Get("pet")))
        mover:ClearAllPoints()
        mover:SetPoint("CENTER",ui,"BOTTOMLEFT",cursorX+40,cursorY+20)
        Check(EM2.Ticker.ApplyExternalDrag(drag),"combat external preview refused")
    else
        Check(mover:GetScript("OnMouseDown")(mover,"LeftButton")==true,"combat drag refused")
        cursorX,cursorY=cursorX+40,cursorY+20
        ticker:GetScript("OnUpdate")(ticker,.016)
    end
    local savedX,savedY=conf.offsetX,conf.offsetY
    local writes,oldSetPoint=0,frame.SetPoint
    frame.SetPoint=function(self,...) writes=writes+1; return oldSetPoint(self,...) end
    Check(Public("MSUF_IsConfigCombatLocked")("PLAYER_REGEN_DISABLED"),"combat edge not locked")
    Check(not env.InCombatLockdown(),"combat edge fixture entered native lockdown too early")
    if method=="stop" then EM2.Ticker.Stop(true)
    elseif method=="external" then EM2.Ticker.EndExternalDrag(drag,true)
    else mover:GetScript("OnMouseUp")(mover,"LeftButton") end
    Check(writes==0,method..": combat completion wrote protected position")
    Check(conf.offsetX==savedX and conf.offsetY==savedY,method..": combat completion changed saved offsets")
    frame.SetPoint=oldSetPoint
    Public("MSUF_IsConfigCombatLocked")("PLAYER_REGEN_ENABLED")
    mover:GetScript("OnMouseUp")(mover,"LeftButton")
    EM2.Ticker.Start()
    world.widgets:RunTimers()
end
-- A pending numeric edit must settle before a new mouse gesture captures its
-- position. Otherwise a later native blur overwrites the completed drag.
db.general.editModeSnapEnabled=false
for _, key in ipairs({ "player", "target", "focus", "pet", "pettarget", "targettarget", "focustarget", "boss" }) do
    for _, axis in ipairs({ "xBox", "yBox" }) do
        frame,conf=core.UF.frames[UnitToken(key)],db[key]
        frame:SetScale(1)
        conf.point,conf.relativePoint,conf.anchorToUnitframe="CENTER","CENTER","GLOBAL"
        conf.anchorFrameName,conf.screenPositionMode=nil,nil
        conf.offsetX,conf.offsetY=-200,-80
        core.UF.Config.RefreshUnit(UnitToken(key))
        core.UF.Factory.ForceReanchor(key)
        EM2.Movers.SyncKey(key)
        mover=EM2.Movers.Get(key)
        EM2.UnitPopup.Open(key,mover)
        local popup
        for _, candidate in ipairs(world.widgets.frames) do
            if candidate.frameName=="MSUF_EM2_UnitPopup" then popup=candidate end
        end
        local box=assert(popup and popup[axis])
        EM2.Undo.Clear()
        local initialX,initialY=conf.offsetX,conf.offsetY
        box.focused=true
        box:SetText(tostring(tonumber(box:GetText())+50))
        cursorX,cursorY=Physical(mover)
        mouseDown=true
        Check(mover:GetScript("OnMouseDown")(mover,"LeftButton")==true,key.." "..axis..": focused drag rejected")
        Check(not box:HasFocus(),key.." "..axis..": pending input survived drag start")
        local typedX,typedY=conf.offsetX,conf.offsetY
        local startX,startY=Physical(frame)
        cursorX,cursorY=cursorX+100,cursorY+40
        ticker:GetScript("OnUpdate")(ticker,.06)
        world.widgets:RunTimers()
        local dragX,dragY=Physical(frame)
        Check(Near(dragX,startX+100) and Near(dragY,startY+40),key.." "..axis..": drag lost settled starting position")
        mouseDown=false
        mover:GetScript("OnMouseUp")(mover,"LeftButton")
        mover:GetScript("OnDragStop")(mover,"LeftButton")
        world.widgets:RunTimers()
        local savedX,savedY=conf.offsetX,conf.offsetY
        box:ClearFocus()
        world.widgets:RunTimers()
        core.UF.Factory.ForceReanchor(key)
        local replayX,replayY=Physical(frame)
        Check(Near(dragX,replayX) and Near(dragY,replayY),key.." "..axis..": native blur snapped back the drag")
        Check(conf.offsetX==savedX and conf.offsetY==savedY,key.." "..axis..": native blur rewrote saved X/Y")
        Check(EM2.Undo.DoUndo() and conf.offsetX==typedX and conf.offsetY==typedY,key.." "..axis..": Undo did not preserve typed edit")
        Check(EM2.Undo.DoUndo() and conf.offsetX==initialX and conf.offsetY==initialY,key.." "..axis..": typed edit lacked its own Undo")
        Check(EM2.Undo.DoRedo() and conf.offsetX==typedX and conf.offsetY==typedY,key.." "..axis..": typed edit Redo failed")
        Check(EM2.Undo.DoRedo() and conf.offsetX==savedX and conf.offsetY==savedY,key.." "..axis..": drag Redo failed")
        EM2.UnitPopup.Close()
    end
end

-- Native drag completion can omit OnClick. The next click on the same mover
-- still opens the single-frame popup, including when Ctrl is held.
do
    env.IsControlKeyDown = function() return true end
    EM2.State.SetUnitKey("player")
    cursorX,cursorY=Physical(mover)
    mouseDown=true
    Check(mover:GetScript("OnMouseDown")(mover,"LeftButton")==true,"Ctrl click rejected by mover")
    mouseDown=false
    Check(mover:GetScript("OnMouseUp")(mover,"LeftButton")==false,"stationary Ctrl click persisted movement")
    mover:GetScript("OnClick")(mover,"LeftButton")
    Check(EM2.State.GetUnitKey()=="boss" and EM2.UnitPopup.IsOpen(),"first click after drag did not open the single-frame popup")
    EM2.UnitPopup.Close()
end

-- A wide raid block must move by one unit across X = 0, even while its
-- bounds still span the screen center. Drive the real popup's +/- callbacks.
do
    env.IsShiftKeyDown = function() return false end
    env.IsControlKeyDown = function() return false end
    env.IsAltKeyDown = function() return false end
    ui:SetScale(0.8)
    local GF = core.GF
    GF.EnsureDB()
    local raid = GF.GetConf("raid")
    raid.enabled, raid.width, raid.height, raid.spacing = true, 150, 50, 4
    raid.unitsPerColumn, raid.maxColumns = 5, 2
    raid.preserveRaidGroups, raid.layoutTiersEnabled = false, false
    raid.point, raid.relativePoint, raid.growth = "CENTER", "CENTER", "DOWN"
    raid.anchorFrameName, raid.screenPositionMode = nil, nil
    raid.offsetX, raid.offsetY, raid.positionMode = 0, -220, "GRID_BOUNDS_V2"

    for _, candidate in ipairs(world.widgets.frames) do
        local handler = candidate:GetScript("OnEvent")
        if candidate:IsEventRegistered("PLAYER_LOGIN") and handler
            and debug.getinfo(handler, "S").source:find("Group_EM2", 1, true) then
            handler(candidate, "PLAYER_LOGIN")
        end
    end
    world.widgets:RunTimers()
    Public("MSUF_GF_EM2_ShowPreview")()
    world.widgets:RunTimers()
    local registry = assert(EM2.Registry.Get("gf_raid"), "raid mover missing")
    local groupMover = assert(registry.getFrame(), "raid mover has no frame")
    local logical = assert(groupMover._msufGFLogicalAnchor, "standalone raid preview anchor missing")
    NativeGeometry(logical)
    NativeGeometry(groupMover)
    NativeGeometry(GF._previewContainer.raid)
    NativeGeometry(GF._previewLayoutFrame.raid)
    for _, sample in ipairs(GF._previewFrames.raid) do NativeGeometry(sample) end

    Public("MSUF_EM2_ShowGFPopup")("raid")
    local popup
    for _, candidate in ipairs(world.widgets.frames) do
        if candidate.frameName == "MSUF_EM2_GFPopup_raid" then popup = candidate end
    end
    assert(popup and popup.xBox and popup.yBox, "raid position boxes missing")
    local xBox, yBox = popup.xBox, popup.yBox
    local summarize = EM2.HUDSelection.FormatSelectionSummary
    Check(summarize("Raid", -0.25, 0.25, 304, 266, "gf_raid") == "Raid   X -0.25   Y 0.25   W 304   H 266",
        "compact group summary lost fractional offsets")
    Check(summarize("External", -0.25, 0.25, 304, 266, "external:test")
        == string.format("%s   X %d   Y %d   W %d   H %d", "External", -0.25, 0.25, 304, 266),
        "compact external summary changed its coordinate format")
    local function FindSteps(box)
        local _, plus = box:GetPoint()
        local minus
        for _, candidate in ipairs(world.widgets.frames) do
            local _, relative = candidate:GetPoint()
            if relative == box and candidate:GetScript("OnClick") then minus = candidate end
        end
        assert(minus and plus and plus:GetScript("OnClick"), "raid step buttons missing")
        return minus, plus
    end
    local xMinus, xPlus = FindSteps(xBox)
    local yMinus, yPlus = FindSteps(yBox)
    local function Click(button)
        button:GetScript("OnClick")(button)
    end
    local function Enter(box, value)
        box:SetText(tostring(value))
        box:GetScript("OnEnterPressed")(box)
        world.widgets:RunTimers()
    end
    local function CheckRaidSteps(label, anchor, sample)
        popup.Sync()
        local savedX, savedY = raid.offsetX, raid.offsetY
        local startX, startY = CenterUI(anchor)
        Check(tonumber(xBox:GetText()) == savedX and tonumber(yBox:GetText()) == savedY,
            label .. ": displayed position is not the saved anchor offset")
        Public("MSUF_EM2_HideGFPopup")("raid")
        Public("MSUF_EM2_ShowGFPopup")("raid")
        Enter(popup.wBox, 155)
        local unchangedX, unchangedY = CenterUI(anchor)
        Check(raid.offsetX == savedX and raid.offsetY == savedY and unchangedX == startX and unchangedY == startY,
            label .. ": opening, reopening or resizing moved a saved position")
        Enter(popup.wBox, 150)

        for _, offsets in ipairs({ { -240, 110 }, { 260, -160 }, { 0, 0 } }) do
            local oldY = raid.offsetY
            Enter(xBox, offsets[1])
            Check(raid.offsetX == offsets[1] and raid.offsetY == oldY, label .. ": typed X changed the wrong offset")
            Enter(yBox, offsets[2])
            local x, y = CenterUI(anchor)
            local screenX, screenY = ui:GetCenter()
            Check(raid.offsetX == offsets[1] and raid.offsetY == offsets[2],
                label .. ": typed Y changed the wrong offset")
            Check(math.abs(x - screenX - offsets[1]) < 0.001 and math.abs(y - screenY - offsets[2]) < 0.001,
                label .. ": typed offsets missed their target on screen")
            Check(tonumber(xBox:GetText()) == offsets[1] and tonumber(yBox:GetText()) == offsets[2],
                label .. ": the readout differs from the typed offsets")
        end

        local centerX, centerY = CenterUI(anchor)
        local sampleX, sampleY
        if sample then sampleX, sampleY = CenterUI(sample) end
        for _, step in ipairs({ { xMinus, -1, 0 }, { yPlus, -1, 1 }, { xPlus, 0, 1 },
            { xPlus, 1, 1 }, { yMinus, 1, 0 }, { xMinus, 0, 0 } }) do
            Click(step[1])
            Check(tonumber(xBox:GetText()) == step[2] and tonumber(yBox:GetText()) == step[3],
                label .. ": the readout did not advance immediately")
            world.widgets:RunTimers()
            local _, hudX, hudY = EM2.HUDSelection.SelectionValues("gf_raid")
            Check(hudX == step[2] and hudY == step[3], label .. ": the HUD still shows edge coordinates")
            local x, y = CenterUI(anchor)
            Check(raid.offsetX == step[2] and raid.offsetY == step[3]
                and math.abs(x - centerX - step[2]) < 0.001 and math.abs(y - centerY - step[3]) < 0.001,
                label .. ": a step did not move the requested axis by one")
            if sample then
                local sx, sy = CenterUI(sample)
                Check(math.abs(sx - sampleX - step[2]) < 0.001 and math.abs(sy - sampleY - step[3]) < 0.001,
                    label .. ": visible preview did not follow the new position")
            end
        end

        xBox.focused = true
        xBox:SetText("-55")
        Click(xPlus)
        Click(xPlus)
        Check(xBox:GetText() == "-53", label .. ": focused readout failed to show two steps")
        xBox:ClearFocus()
        world.widgets:RunTimers()
        Check(raid.offsetX == -53 and raid.offsetY == 0, label .. ": blur replayed a pending position")

        EM2.Undo.Clear()
        xBox.focused = true
        Click(xPlus)
        world.widgets:RunTimers(300)
        EM2.Undo.DoUndo()
        world.widgets:RunTimers(300)
        Check(raid.offsetX == -53 and xBox:GetText() == "-53" and xBox:HasFocus(),
            label .. ": focused X did not reflect Undo")
        EM2.Undo.DoRedo()
        world.widgets:RunTimers(300)
        Check(raid.offsetX == -52 and xBox:GetText() == "-52" and xBox:HasFocus(),
            label .. ": focused X did not reflect Redo")
        xBox:SetText("-60")
        EM2.Undo.DoUndo()
        world.widgets:RunTimers(300)
        Check(raid.offsetX == -53 and xBox:GetText() == "-60", label .. ": history discarded an active draft")
        EM2.QuickPopup.DiscardFocusedEdits()
        popup.Sync()
        Enter(xBox, "1e300")
        Check(raid.offsetX == -53 and xBox:GetText() == "-53", label .. ": invalid offset replaced the saved position")

        world.widgets:SetCombat(true)
        xBox.focused = true
        xBox:SetText("-123")
        xBox:ClearFocus()
        Check(raid.offsetX == -53 and xBox._msufShownText == "-53", label .. ": combat acknowledged an uncommitted draft")
        world.widgets:SetCombat(false)
        popup.Sync()

        local tier = sample and "tier40" or "tier10"
        raid.layoutTiersEnabled = true
        raid[tier .. "Position"] = false
        popup.Sync()
        xBox.focused = true
        xBox:SetText("777")
        raid[tier .. "Position"], raid[tier .. "X"], raid[tier .. "Y"] = true, 22.25, -15.25
        popup.Sync()
        xBox:ClearFocus()
        Check(xBox:GetText() == "22.25" and yBox:GetText() == "-15.25"
            and raid[tier .. "X"] == 22.25 and raid.offsetX == -53,
            label .. ": a focused base-layout draft was replayed into a different tier")
        Enter(xBox, 18)
        Check(raid[tier .. "X"] == 18 and raid[tier .. "Y"] == -15.25 and raid.offsetX == -53 and raid.offsetY == 0,
            label .. ": typed tier X wrote into the base layout or the other axis")
        EM2.Undo.Clear()
        xBox.focused = true
        xBox:SetText("777")
        raid.layoutTiersEnabled = false
        xBox:ClearFocus()
        world.widgets:RunTimers(300)
        Check(raid.offsetX == -53 and raid[tier .. "X"] == 18 and not EM2.Undo.CanUndo(),
            label .. ": stale draft changed a tier or added Undo")
        popup.Sync()

        raid.offsetX, raid.offsetY = -2000.25, 0.25
        popup.Sync()
        Check(xBox:GetText() == "-2000.25" and yBox:GetText() == "0.25", label .. ": saved fractions were hidden")
        Click(xMinus)
        Click(xMinus)
        world.widgets:RunTimers()
        Check(raid.offsetX == -2002.25 and raid.offsetY == 0.25,
            label .. ": stepping rounded or reset a saved offset")
    end
    CheckRaidSteps("raid preview", logical, GF._previewFrames.raid[1])
    raid.offsetX, raid.offsetY = 0, -220
    inRaid = true
    GF.InvalidateLayoutRoster()
    assert(GF.SetupHeader("raid", "raid"), "live raid header missing")
    local live = assert(GF.anchors.raid, "live raid anchor missing")
    NativeGeometry(live)
    Public("MSUF_GF_EM2_ShowPreview")()
    world.widgets:RunTimers()
    Check(registry.getFrame()._msufGFLiveAnchor == live, "raid popup did not switch to live bounds")
    CheckRaidSteps("live raid", live)
    Public("MSUF_EM2_HideGFPopup")("raid")
end
assert(#failures==0,"unitframe_editmode_movement_smoke failed:\n"..table.concat(failures,"\n"))
print("unitframe_editmode_movement_smoke: PASS ("..checks.." checks)")
