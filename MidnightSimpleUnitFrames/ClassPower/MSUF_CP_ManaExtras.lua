-- Public mana observations and native-fill cast-cost previews. Duration objects
-- animate the short displays; no ticker or aura scan is involved.
local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "ClassPower/MSUF_CP_ManaExtras.lua")
MSUF.CPBuilders = MSUF.CPBuilders or {}
-- The regeneration pause after spending Mana and the two-second regeneration
-- pulses are game rules of Classic Era, TBC and WoW Forever (no other client
-- has them); their bars need the native duration API.
function MSUF.CPBuilders.ManaRegenTimersSupported()
    local client = MSUF.Client or {}
    local durationUtil = _G.C_DurationUtil
    return (client.IsVanilla == true or client.IsTBC == true or client.IsForever == true)
        and type(durationUtil) == "table" and type(durationUtil.CreateDuration) == "function"
end
-- Bound by MSUF.CPBuilders.ManaExtras: its options table, state and event
-- frame. The resource-extras lifecycle builds the one helper once per session.
local Refresh, StartTick
local function Number(owner, value)
    local E, state, events = owner.E, owner.state, owner.events
 return E.NotSecret(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function HidePrediction(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if state.prediction then
        state.prediction:Hide()
    end
    state.cost=nil
    state.hasCost=false
end
local function HideFive(owner)
    local E, state, events = owner.E, owner.state, owner.events

    state.fiveUntil=nil
    if state.five then
        state.five:Hide()
    end
end
local function HideTick(owner)
    local E, state, events = owner.E, owner.state, owner.events

    state.tickUntil=nil
    if state.tick then
        state.tick:Hide()
    end
end
-- One persistent callback per strip: a later start moves the deadline and
-- the earlier callback finds it in the future. No timer objects.
local function ExpireFive(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if state.fiveUntil and GetTime() >= state.fiveUntil - .01 then
        HideFive(owner)
        if state.tickUntil then state.tick:Show() end
    end
end
local function ExpireTick(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if state.tickUntil and GetTime() >= state.tickUntil - .01 then
        HideTick(owner)
        StartTick(owner, state.lastGainAt)
    end
end
local function Color(owner, bar,key,r,g,b)
    local E, state, events = owner.E, owner.state, owner.events

    local color=E.db.bars[key]
    if type(color)=="table" then r,g,b=color[1],color[2],color[3] end
    if bar.markerStyle == "spark" then
        bar.manaSpark:SetVertexColor(r,g,b,1)
        bar.manaGlow:SetVertexColor(r,g,b,math.max(0,math.min(1,tonumber(E.db.bars.manaRegenSparkAlpha) or .35)))
    elseif bar.SetStatusBarColor then bar:SetStatusBarColor(r,g,b,1) else bar:SetVertexColor(r,g,b,1) end
end
local function PublicRegion(owner, region)
    local E, state, events = owner.E, owner.state, owner.events

    if not E.NotSecret(region) or not region then return false end
    if region.IsForbidden then
        local forbidden=region:IsForbidden()
        if not E.NotSecret(forbidden) or forbidden then return false end
    end
    return true
end
-- The native fill is invisible; its moving edge carries the marker inside Mana.
-- Geometry is configured only by the out-of-combat host refresh.
local function LayoutMarker(owner, bar, host, key)
    local E, state, events = owner.E, owner.state, owner.events

    local width, height = host:GetWidth(), host:GetHeight()
    local orientation, reverse = host:GetOrientation(), host:GetReverseFill()
    bar.markerReady = false
    if not Number(owner, width) or width <= 0 or not Number(owner, height) or height <= 0
        or not E.NotSecret(orientation) or not E.NotSecret(reverse) then return end
    bar:SetParent(host)
    bar:ClearAllPoints()
    bar:SetAllPoints(host)
    bar:SetSize(width, height)
    bar:SetFrameLevel(host:GetFrameLevel() + 2)
    bar:SetOrientation(orientation)
    bar:SetReverseFill(reverse)
    local fill = bar:GetStatusBarTexture()
    bar.markerStyle = E.db.bars.manaRegenStyle == "bars" and "bars" or "spark"
    if bar.markerStyle == "bars" then
        bar:ClearAllPoints()
        local five = key == "five"
        bar:SetPoint(five and "BOTTOMLEFT" or "TOPLEFT", host, five and "TOPLEFT" or "BOTTOMLEFT", 0, five and 1 or -1)
        bar:SetPoint(five and "BOTTOMRIGHT" or "TOPRIGHT", host, five and "TOPRIGHT" or "BOTTOMRIGHT", 0, five and 1 or -1)
        bar:SetHeight(five and 3 or 2)
        bar:SetOrientation("HORIZONTAL")
        bar:SetReverseFill(false)
        fill:SetAlpha(1)
        if bar.manaSpark then bar.manaSpark:Hide() bar.manaGlow:Hide() end
        bar.markerReady = true
        return
    end
    fill:SetAlpha(0)
    if not bar.manaSpark then
        bar.manaSpark = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY"))
        bar.manaSpark:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar.manaGlow = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY"))
        bar.manaGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        bar.manaGlow:SetBlendMode("ADD")
        bar:EnableMouse(false)
    end
    local spark, vertical = bar.manaSpark, orientation == "VERTICAL"
    spark:ClearAllPoints()
    local edge = vertical and (reverse and "BOTTOM" or "TOP") or (reverse and "LEFT" or "RIGHT")
    spark:SetPoint("CENTER", fill, edge)
    local thickness = math.max(1, math.min(8, tonumber(E.db.bars.manaRegenSparkWidth) or 2))
    spark:SetSize(vertical and width or math.min(thickness, width), vertical and math.min(thickness, height) or height)
    local glow = bar.manaGlow
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", spark, "CENTER")
    glow:SetSize(vertical and width + 4 or thickness + 10, vertical and thickness + 10 or height + 4)
    glow:Show()
    spark:Show()
    bar.markerReady = true
end
local function MarkerAlpha(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if not state.fullCurve or not UnitPowerPercent then return end
    local alpha = UnitPowerPercent("player", 0, true, state.fullCurve)
    if E.NotSecret(alpha) and type(alpha) ~= "number" then return end
    for _, bar in ipairs(state.markers) do
        if bar.markerStyle == "spark" then
            bar.manaSpark:SetAlpha(alpha)
            bar.manaGlow:SetAlpha(alpha)
        else bar:GetStatusBarTexture():SetAlpha(alpha) end
    end
end
local function Editing(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if state.editActive ~= nil then return state.editActive end
    return _G.MSUF_UnitEditModeActive == true
end
local function HideSamples(owner)
    local E, state, events = owner.E, owner.state, owner.events

    for _, bar in pairs(state.samples or {}) do bar:Hide() end
end
-- Public sample values feed the same strips and masked cost surface as live
-- observations. Edit Mode and menu previews retain no second set of regions.
local function PaintSampleBars(owner, host)
    local E, state, events = owner.E, owner.state, owner.events

    HideSamples(owner)
    if not Editing(owner) or not PublicRegion(owner, host) then return end
    state.samples = state.samples or {}
    state.samples.five, state.samples.tick, state.samples.cost = state.five, state.tick, state.prediction
    Color(owner, state.five, "manaRegenPauseColor", 1, .65, .2)
    Color(owner, state.tick, "manaGainPulseColor", .3, 1, .7)
    for _, bar in ipairs(state.markers) do
        if bar.markerStyle == "spark" then bar.manaSpark:SetAlpha(1) bar.manaGlow:SetAlpha(1)
        else bar:GetStatusBarTexture():SetAlpha(1) end
    end
    state.five:SetMinMaxValues(0, 1)
    state.tick:SetMinMaxValues(0, 1)
    state.five:SetValue(.6)
    state.tick:SetValue(.5)
    state.five:SetShown(state.rule == true)
    state.tick:SetShown(state.ticks == true)
    if state.prediction then
        Color(owner, state.prediction, "manaCostColor", .7, .7, 1)
        state.prediction:SetMinMaxValues(0, 1)
        state.prediction:SetValue(.18)
        state.prediction:SetShown(state.preview == true and state.predictionReady == true)
    end
end
-- Live Edit Mode owns an isolated instance of these same painters. Its
-- sample values never replace a running timer on the live instance.
local function Samples(owner, host)
    local E, state, events = owner.E, owner.state, owner.events

    HideSamples(owner)
    if not Editing(owner) or not PublicRegion(owner, host) then return end
    if not state.samplePainter then
        local sampleEnv = setmetatable({ sample = true }, { __index = E })
        state.samplePainter = MSUF.CPBuilders.ManaExtras(sampleEnv)
    end
    state.samples = state.samplePainter.PaintSample(host)
end
--- The cast-cost preview surface: a native fill masked like the Mana bar's own,
--- built only from public regions; any restricted or unexpected state hides it.
local function EnsurePrediction(owner, host)
    local E, state, events = owner.E, owner.state, owner.events

    local fill=host.GetStatusBarTexture and host:GetStatusBarTexture()
    local width,height=host:GetWidth(),host:GetHeight()
    local orientation="HORIZONTAL"
    if host.GetOrientation then orientation=host:GetOrientation() end
    local reverse=false
    if host.GetReverseFill then reverse=host:GetReverseFill() end
    if not E.NotSecret(fill) or not fill or not host.CreateMaskTexture
        or not Number(owner, width) or width<=0 or not Number(owner, height) or height<=0
        or not E.NotSecret(orientation) or not E.NotSecret(reverse) then
        HidePrediction(owner)
        return
    end
    local vertical=orientation=="VERTICAL"
    if fill.IsForbidden then
        local forbidden=fill:IsForbidden()
        if not E.NotSecret(forbidden) or forbidden then
            HidePrediction(owner)
            return
        end
    end
    if not fill.GetNumMaskTextures or not fill.GetMaskTexture then
        HidePrediction(owner)
        return
    end
    local count=fill:GetNumMaskTextures()
    if not Number(owner, count) or count<0 or count>32 or count%1~=0 then
        HidePrediction(owner)
        return
    end
    local masks={}
    for index=1,count do
        local mask=fill:GetMaskTexture(index)
        if not PublicRegion(owner, mask) then
            HidePrediction(owner)
            return
        end
        masks[#masks+1]=mask
    end
    local shaped=host._msufPowerShapeActive
    if not E.NotSecret(shaped) then
        HidePrediction(owner)
        return
    end
    local shapeAsset=shaped and host._msufTexture
    if shaped and (not E.NotSecret(shapeAsset) or type(shapeAsset)~="string" or shapeAsset=="") then
        HidePrediction(owner)
        return
    end
    if not state.prediction then
        state.prediction=PixelLayoutRegion(CreateFrame("StatusBar",nil,host))
        state.prediction:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        state.prediction:Hide()
        state.predictionFill=PixelLayoutRegion(state.prediction:GetStatusBarTexture())
        if not PublicRegion(owner, state.predictionFill) then
            HidePrediction(owner)
            return
        end
        state.predictionFill:SetDrawLayer("OVERLAY",3)
        state.predictionMask=PixelLayoutRegion(host:CreateMaskTexture(nil,"OVERLAY"))
        state.predictionMask:SetTexture("Interface\\Buttons\\WHITE8X8","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
        if not state.predictionFill.AddMaskTexture or not state.predictionFill.RemoveMaskTexture then
            HidePrediction(owner)
            return
        end
        state.predictionFill:AddMaskTexture(state.predictionMask)
        state.predictionMasked=true
    end
    if not state.predictionMasked then
        HidePrediction(owner)
        return
    end
    -- Borrow references only: shared native masks keep their owner, anchors
    -- and visibility. All hierarchy queries and binding changes stay OOC.
    local old=state.borrowedMasks or {}
    for _,mask in ipairs(old) do
        if not PublicRegion(owner, mask) then
            HidePrediction(owner)
            return
        end
    end
    for _,mask in ipairs(old) do state.predictionFill:RemoveMaskTexture(mask) end
    state.borrowedMasks={}
    state.predictionFill:RemoveMaskTexture(state.predictionMask)
    if state.shapeMasked then
        state.predictionFill:RemoveMaskTexture(state.shapeMask)
        state.shapeMasked=false
    end
    if shaped then
        if not state.shapeMask then state.shapeMask=PixelLayoutRegion(host:CreateMaskTexture(nil,"OVERLAY")) end
        state.shapeMask:SetParent(host)
        state.shapeMask:ClearAllPoints()
        state.shapeMask:SetAllPoints(host)
        state.shapeMask:SetTexture(shapeAsset,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
        state.shapeMask:Show()
    elseif state.shapeMask then
        if state.shapeMasked then
            state.predictionFill:RemoveMaskTexture(state.shapeMask)
            state.shapeMasked=false
        end
        state.shapeMask:Hide()
    end
    state.prediction:SetParent(host)
    state.prediction:ClearAllPoints()
    state.prediction:SetSize(width,height)
    state.prediction:SetFrameLevel(host:GetFrameLevel())
    state.prediction:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    state.prediction:SetReverseFill(not reverse)
    local edge=vertical and (reverse and "BOTTOM" or "TOP") or (reverse and "LEFT" or "RIGHT")
    state.prediction:SetPoint(edge,fill,edge,0,0)
    state.predictionMask:SetParent(host)
    state.predictionMask:ClearAllPoints()
    state.predictionMask:SetAllPoints(host)
    state.predictionMask:Show()
    state.predictionFill:AddMaskTexture(state.predictionMask)
    if shaped then
        state.predictionFill:AddMaskTexture(state.shapeMask)
        state.shapeMasked=true
    end
    for _,mask in ipairs(masks) do state.predictionFill:AddMaskTexture(mask) end
    state.borrowedMasks=masks
    state.fill,state.width,state.height,state.vertical,state.reverse=fill,width,height,vertical,reverse
    state.predictionReady=true
end
local function Ensure(owner, host)
    local E, state, events = owner.E, owner.state, owner.events

    HideSamples(owner)
    if not state.five then
        state.five=PixelLayoutRegion(CreateFrame("StatusBar",nil,host))
        state.tick=PixelLayoutRegion(CreateFrame("StatusBar",nil,host))
        state.markers = {state.five, state.tick}
        for _,bar in ipairs({state.five,state.tick}) do
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:Hide()
        end
        if C_DurationUtil and C_DurationUtil.CreateDuration then
            state.fiveDuration=C_DurationUtil.CreateDuration()
            state.tickDuration=C_DurationUtil.CreateDuration()
        end
    end
    state.host=host
    if not host._msufManaExtrasSizeHook and host.HookScript then
        host._msufManaExtrasSizeHook=true
        host:HookScript("OnSizeChanged",function(self) if state.host==self and E.RequestRefresh then E.RequestRefresh() end end)
    end
    LayoutMarker(owner, state.five, host, "five")
    LayoutMarker(owner, state.tick, host, "tick")
    if not state.fullCurve and C_CurveUtil and C_CurveUtil.CreateCurve then
        state.fullCurve = C_CurveUtil.CreateCurve()
        state.fullCurve:SetType(Enum.LuaCurveType.Step)
        state.fullCurve:AddPoint(0, 1)
        state.fullCurve:AddPoint(1, 0)
    end
    state.predictionReady=false
    EnsurePrediction(owner, host)
end
local function Timer(owner, bar,duration,seconds,start)
    local E, state, events = owner.E, owner.state, owner.events

    if not bar.markerReady or not duration or not bar.SetTimerDuration then return false end
    duration:SetTimeFromStart(start or GetTime(),seconds)
    local direction = seconds == 2 and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime
    bar:SetTimerDuration(duration,Enum.StatusBarInterpolation.Immediate,direction)
    bar:Show()
    return true
end
StartTick = function(owner, start)
    local E, state = owner.E, owner.state
    if not state.ticks or not state.host or state.suspended or state.editActive or E.sample then return end
    if state.host.IsVisible and not state.host:IsVisible() then return end
    if state.last and state.maximum and state.last >= state.maximum then return end
    local now = GetTime()
    start = start or now
    start = now - (now - start) % 2
    if Timer(owner, state.tick, state.tickDuration, 2, start) then
        state.lastGainAt = start
        state.tickUntil = start + 2
        state.tick:SetShown(state.tick.markerStyle == "bars" or not state.fiveUntil)
        C_Timer.After(state.tickUntil - now, owner.expireTick)
    end
end
-- Restricted mana cannot be compared. A public event timestamp supplies an
-- estimated tick phase; an adjacent paid cast cancels that observation.
local function ConfirmTick(owner)
    local E, state, events = owner.E, owner.state, owner.events

    local at = state.pendingTickAt
    if not at or GetTime() < at + .1 then return end
    state.pendingTickAt = nil
    if not state.lastSpendAt or math.abs(at - state.lastSpendAt) > .1 then StartTick(owner, at) end
end
local function ObserveMana(owner, event)
    local E, state, events = owner.E, owner.state, owner.events

    MarkerAlpha(owner)
    if not state.ticks then
        state.last, state.maximum = nil, nil
        return
    end
    local current, maximum = UnitPower("player", 0), UnitPowerMax("player", 0)
    if not E.NotSecret(current) or not E.NotSecret(maximum) then
        state.last, state.maximum = nil, nil
        if event then
            state.pendingTickAt = GetTime()
            C_Timer.After(.11, owner.confirmTick)
        end
        return
    end
    state.pendingTickAt = nil
    if not Number(owner, current) or not Number(owner, maximum) or maximum <= 0 then
        state.last, state.maximum = nil, nil
        HideTick(owner)
        return
    end
    if current >= maximum then
        HideTick(owner)
        if state.five then state.five:Hide() end
    elseif state.last and state.maximum == maximum and current > state.last then
        StartTick(owner, GetTime())
    elseif state.fiveUntil then
        state.five:Show()
    end
    state.last, state.maximum = current, maximum
end
local function Prediction(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if not state.preview or not state.host or not state.hasCost then return end
    if not state.predictionReady then
        HidePrediction(owner)
        return
    end
    local maximum=UnitPowerMax("player",0)
    local width,height=state.host:GetWidth(),state.host:GetHeight()
    local fill=state.host.GetStatusBarTexture and state.host:GetStatusBarTexture()
    if E.NotSecret(maximum) and (not Number(owner, maximum) or maximum<=0) or not Number(owner, width) or width~=state.width
        or not Number(owner, height) or height~=state.height or not E.NotSecret(fill) or not fill or fill~=state.fill then
        HidePrediction(owner)
        return
    end
    if fill.IsForbidden then
        local forbidden=fill:IsForbidden()
        if not E.NotSecret(forbidden) or forbidden then
            HidePrediction(owner)
            return
        end
    end
    -- The engine normalizes absolute cost against maximum mana. Neither
    -- restricted value enters Lua arithmetic or layout; the preanchored
    -- inverse fill follows current mana and host masks clip underflow.
    state.prediction:SetMinMaxValues(0,maximum)
    state.prediction:SetValue(state.cost)
    state.prediction:SetShown(not E.NotSecret(state.cost) or state.cost>0)
end
local function ManaCost(owner, spellID,allowRestricted)
    local E, state, events = owner.E, owner.state, owner.events

    local native=C_Spell and C_Spell.GetSpellPowerCost
    local restricted=not E.NotSecret(spellID)
    if restricted then
        -- Restricted identifiers exist on the Midnight engine only (WoW
        -- Forever included), where C_Spell accepts them.
        if not MSUF.Client.IsRetail or not native then return end
    elseif not Number(owner, spellID) then return end
    local costs
    if native then costs=native(spellID)
    elseif GetSpellPowerCost then costs=GetSpellPowerCost(spellID) end
    if not E.NotSecret(costs) or type(costs)~="table" or canaccesstable and not canaccesstable(costs) then return end
    for _,cost in pairs(costs) do
        if E.NotSecret(cost) and type(cost)=="table" and (not canaccesstable or canaccesstable(cost))
            and Number(owner, cost.type) and cost.type==0 then
            local value=cost.cost
            if not E.NotSecret(value) then
                if allowRestricted then return value,true end
            elseif Number(owner, value) and value>=0 then return value,true end
        end
    end
end
local function CastCost(owner, spellID)
    local E, state, events = owner.E, owner.state, owner.events

    if not state.preview then return end
    HidePrediction(owner)
    state.cost,state.hasCost=ManaCost(owner, spellID,true)
    Prediction(owner)
end
local function OnEvent(owner, self,event,unit,powerToken,spellID)
    local E, state, events = owner.E, owner.state, owner.events

    if unit~="player" or state.suspended then return end
    if event=="UNIT_SPELLCAST_SUCCEEDED" and (state.rule or state.ticks) then
        local cost=ManaCost(owner, spellID)
        if cost and cost > 0 then
            state.lastSpendAt = GetTime()
            state.pendingTickAt = nil
        end
        if state.rule and cost and cost>0 and Timer(owner, state.five,state.fiveDuration,5) then
            state.fiveUntil=GetTime()+5
            if state.tick.markerStyle ~= "bars" then state.tick:Hide() end
            MarkerAlpha(owner)
            C_Timer.After(5,owner.expireFive)
        end
    end
    if event=="UNIT_POWER_FREQUENT" or event=="UNIT_POWER_UPDATE" then
        if powerToken and powerToken~="MANA" then return end
        ObserveMana(owner, true)
    elseif event=="UNIT_MAXPOWER" then
        state.last=nil
        ObserveMana(owner)
        Prediction(owner)
    elseif event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
        HidePrediction(owner)
        CastCost(owner, spellID)
    elseif state.preview then
        -- An instant spell allowed during another cast must not clear that
        -- cast's preview. Native C_Spell accepts restricted identifiers;
        -- only a public missing/invalid cast ID falls back to the channel.
        local current=select(9,UnitCastingInfo("player"))
        if E.NotSecret(current) and not Number(owner, current) then current=select(8,UnitChannelInfo("player")) end
        if not E.NotSecret(current) or Number(owner, current) then CastCost(owner, current) else HidePrediction(owner) end
    end
end
local function Disable(owner)
    local E, state, events = owner.E, owner.state, owner.events

    HideSamples(owner)
    if state.editListener and MSUF.EditModeAPI then
        MSUF.EditModeAPI.UnregisterSessionListener("MSUF.ManaExtras")
        state.editListener, state.editActive = nil, nil
    end
    events:UnregisterAllEvents()
    HideFive(owner)
    HideTick(owner)
    HidePrediction(owner)
    state.last=nil
    state.maximum=nil
    state.host=nil
    state.pendingTickAt, state.lastGainAt, state.lastSpendAt = nil, nil, nil
    if state.predictionMask then state.predictionMask:Hide() end
    if state.shapeMask then state.shapeMask:Hide() end
    if not (InCombatLockdown and InCombatLockdown()) and state.prediction then
        local retained={}
        for _,mask in ipairs(state.borrowedMasks or {}) do
            if PublicRegion(owner, mask) then state.predictionFill:RemoveMaskTexture(mask) else retained[#retained+1]=mask end
        end
        state.borrowedMasks=retained
    end
    state.fill=nil
    state.predictionReady=false
end
-- The bar that shows Mana now: the alternative mana bar, or the Player
-- power bar while it shows Mana. false: no public owner to resolve.
local function ResolveHost(owner)
    local E, state, events = owner.E, owner.state, owner.events

    local player=E.GetPlayerFrame()
    if not E.NotSecret(player) then return false end
    local powerBar=player and player.targetPowerBar
    if not E.NotSecret(powerBar) then return false end
    local host=E.AM.visible and E.AM.bar or powerBar
    local primary
    if Editing(owner) then primary=PublicRegion(owner, powerBar) and powerBar._msufPowerType
    else primary=UnitPowerType("player") end
    local displayMana=PublicRegion(owner, powerBar) and powerBar._msufPowerDisplayMana
    local displayed=E.NotSecret(displayMana) and displayMana==true
    if not E.AM.visible and not displayed and (not Number(owner, primary) or primary~=0) then host=nil end
    return host
end
-- Combat: a shapeshift moved Mana to another bar (or off every bar). The
-- helper is only rebound out of combat (the lifecycle owner rebuilds it at
-- combat end); until then it hides what it drew on a bar that no longer
-- shows Mana and ignores the events.
local function PowerChanged(owner)
    local E, state, events = owner.E, owner.state, owner.events

    if not state.host then return end
    local suspended=ResolveHost(owner)~=state.host
    if suspended==(state.suspended==true) then return end
    state.suspended=suspended or nil
    if suspended then
        HideFive(owner)
        HideTick(owner)
        state.pendingTickAt = nil
        HidePrediction(owner)
    end
end
Refresh = function(owner)
    local E, state, events = owner.E, owner.state, owner.events
    if not Editing(owner) then HideSamples(owner) end
    if InCombatLockdown and InCombatLockdown() then
        state.pending=true
        return
    end
    state.pending=false
    state.suspended=nil
    local b=E.db.bars or {}
    local regenTimers=MSUF.CPBuilders.ManaRegenTimersSupported()
    state.rule=regenTimers and b.manaRegenPause==true
    state.ticks=regenTimers and b.manaGainPulse==true
    state.preview=b.manaUpcomingCost==true
    local host=ResolveHost(owner)
    if host==false then
        Disable(owner)
        return
    end
    if not PublicRegion(owner, host) or not (state.rule or state.ticks or state.preview) then
        Disable(owner)
        return
    end
    Ensure(owner, host)
    events:UnregisterAllEvents()
    local api = MSUF.EditModeAPI
    if not state.editListener and api and api.RegisterSessionListener then
        state.editListener = api.RegisterSessionListener("MSUF.ManaExtras", function(active)
            state.editActive = active
            Refresh(owner)
        end) == true
    end
    Color(owner, state.five,"manaRegenPauseColor",1,.65,.2)
    Color(owner, state.tick,"manaGainPulseColor",.3,1,.7)
    if state.prediction then Color(owner, state.prediction,"manaCostColor",.7,.7,1) end
    if not state.rule then HideFive(owner) end
    if not state.ticks then HideTick(owner) end
    if not state.preview then HidePrediction(owner) end
    if state.ticks then
        events:RegisterUnitEvent("UNIT_POWER_FREQUENT","player")
    end
    if state.ticks or state.rule then events:RegisterUnitEvent("UNIT_POWER_UPDATE","player") end
    if state.ticks or state.preview then events:RegisterUnitEvent("UNIT_MAXPOWER","player") end
    if state.preview then
        for _,event in ipairs({"UNIT_SPELLCAST_START","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_STOP",
            "UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_SUCCEEDED"}) do
            events:RegisterUnitEvent(event,"player")
        end
    elseif state.rule or state.ticks then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player")
    end
    if Editing(owner) then
        HideFive(owner)
        HideTick(owner)
        state.pendingTickAt = nil
    end
    Samples(owner, host)
    if MSUF.ResourceVisibility then
        MSUF.ResourceVisibility.BindExtra(state.five, host, b)
        MSUF.ResourceVisibility.BindExtra(state.tick, host, b)
        MSUF.ResourceVisibility.BindExtra(state.prediction, host, b)
        for _, bar in pairs(state.samples or {}) do MSUF.ResourceVisibility.BindExtra(bar, host, b) end
    end
    if not Editing(owner) then
        state.last=nil
        ObserveMana(owner)
        Prediction(owner)
    end
end
local function IsPending(owner)
    local E, state, events = owner.E, owner.state, owner.events
 return state.pending end
function MSUF.CPBuilders.ManaExtras(boundE)
    local owner = { E = boundE, state = {}, events = CreateFrame("Frame") }
    owner.expireFive = function() ExpireFive(owner) end
    owner.expireTick = function() ExpireTick(owner) end
    owner.confirmTick = function() ConfirmTick(owner) end
    owner.events:SetScript("OnEvent", function(...) OnEvent(owner, ...) end)
    return { Refresh = function() Refresh(owner) end, Disable = function() Disable(owner) end,
        PowerChanged = function() PowerChanged(owner) end, IsPending = function() return IsPending(owner) end,
        PaintSample = function(host)
            local E, state = owner.E, owner.state
            local b = E.db.bars
            state.editActive = true
            local supported = MSUF.CPBuilders.ManaRegenTimersSupported()
            state.rule, state.ticks = supported and b.manaRegenPause == true, supported and b.manaGainPulse == true
            state.preview = b.manaUpcomingCost == true
            Ensure(owner, host)
            PaintSampleBars(owner, host)
            return state.samples
        end,
        HideSample = function() HideSamples(owner) end,
    }
end
