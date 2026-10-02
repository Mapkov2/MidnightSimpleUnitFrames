-- Public mana observations and native-fill cast-cost previews. Duration objects
-- animate the short displays; no ticker or aura scan is involved.
local _, MSUF = ...
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...)
    if type(policy) == "string" then return region[policy](region, ...) end
    return region
end
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
local E, state, events
local Refresh
local function Number(value) return E.NotSecret(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function HidePrediction()
    if state.prediction then
        state.prediction:Hide()
    end
    state.cost=nil
    state.hasCost=false
end
local function HideFive()
    state.fiveUntil=nil
    if state.five then
        state.five:Hide()
    end
end
local function HideTick()
    state.tickUntil=nil
    if state.tick then
        state.tick:Hide()
    end
end
-- One persistent callback per strip: a later start moves the deadline and
-- the earlier callback finds it in the future. No timer objects.
local function ExpireFive() if state.fiveUntil and GetTime()>=state.fiveUntil-.01 then HideFive() end end
local function ExpireTick() if state.tickUntil and GetTime()>=state.tickUntil-.01 then HideTick() end end
local function Color(bar,key,r,g,b)
    local color=E.db.bars[key]
    if type(color)=="table" then r,g,b=color[1],color[2],color[3] end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(r,g,b,1) else bar:SetVertexColor(r,g,b,1) end
end
local function PublicRegion(region)
    if not E.NotSecret(region) or not region then return false end
    if region.IsForbidden then
        local forbidden=region:IsForbidden()
        if not E.NotSecret(forbidden) or forbidden then return false end
    end
    return true
end
local function Editing()
    if state.editActive ~= nil then return state.editActive end
    return _G.MSUF_UnitEditModeActive == true
end
local function HideSamples()
    for _, bar in pairs(state.samples or {}) do bar:Hide() end
end
local function DetachSampleMasks()
    local masks = state.sampleMasks
    if not masks or #masks == 0 then return true end
    local bar = state.samples and state.samples.cost
    local fill = bar and bar:GetStatusBarTexture()
    if not PublicRegion(fill) then return false end
    for _, mask in ipairs(masks) do if not PublicRegion(mask) then return false end end
    for _, mask in ipairs(masks) do fill:RemoveMaskTexture(mask) end
    state.sampleMasks = nil
    return true
end
local function SampleBar(key, host)
    state.samples = state.samples or {}
    local bar = state.samples[key]
    if not bar then
        bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, host))
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:EnableMouse(false)
        state.samples[key] = bar
    end
    return bar
end
local function Samples(host)
    HideSamples()
    if not Editing() or not PublicRegion(host) then return end
    for _, key in ipairs({"five", "tick"}) do
        if (key == "five" and state.rule) or (key == "tick" and state.ticks) then
            local bar = SampleBar(key, host)
            bar:SetParent(host)
            bar:ClearAllPoints()
            local point, relative, offset = key == "five" and "BOTTOM" or "TOP",
                key == "five" and "TOP" or "BOTTOM", key == "five" and 1 or -1
            bar:SetPoint(point .. "LEFT", host, relative .. "LEFT", 0, offset)
            bar:SetPoint(point .. "RIGHT", host, relative .. "RIGHT", 0, offset)
            bar:SetHeight(key == "five" and 3 or 2)
            bar:SetFrameLevel(host:GetFrameLevel() + 2)
            Color(bar, key == "five" and "manaRegenPauseColor" or "manaGainPulseColor",
                key == "five" and 1 or .3, key == "five" and .65 or 1, key == "five" and .2 or .7)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(key == "five" and .6 or .5)
            bar:Show()
        end
    end
    if not state.preview or not state.predictionReady then return end
    local old = state.sampleMasks or {}
    for _, mask in ipairs(old) do if not PublicRegion(mask) then return end end
    local bar = SampleBar("cost", host)
    local fill = bar:GetStatusBarTexture()
    if not PublicRegion(fill) then return end
    for _, mask in ipairs(old) do fill:RemoveMaskTexture(mask) end
    state.sampleMasks = {}
    bar:SetParent(host)
    bar:ClearAllPoints()
    bar:SetSize(state.width, state.height)
    bar:SetFrameLevel(host:GetFrameLevel() + 2)
    bar:SetOrientation(state.vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(not state.reverse)
    local edge = state.vertical and (state.reverse and "BOTTOM" or "TOP") or (state.reverse and "LEFT" or "RIGHT")
    bar:SetPoint(edge, state.fill, edge, 0, 0)
    fill:SetDrawLayer("OVERLAY", 3)
    local masks = state.sampleMasks
    masks[#masks + 1] = state.predictionMask
    if state.shapeMasked then masks[#masks + 1] = state.shapeMask end
    for _, mask in ipairs(state.borrowedMasks or {}) do masks[#masks + 1] = mask end
    for _, mask in ipairs(masks) do fill:AddMaskTexture(mask) end
    Color(bar, "manaCostColor", .7, .7, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(.18)
    bar:Show()
end
--- The cast-cost preview surface: a native fill masked like the Mana bar's own,
--- built only from public regions; any restricted or unexpected state hides it.
local function EnsurePrediction(host)
    local fill=host.GetStatusBarTexture and host:GetStatusBarTexture()
    local width,height=host:GetWidth(),host:GetHeight()
    local orientation="HORIZONTAL"
    if host.GetOrientation then orientation=host:GetOrientation() end
    local reverse=false
    if host.GetReverseFill then reverse=host:GetReverseFill() end
    if not E.NotSecret(fill) or not fill or not host.CreateMaskTexture
        or not Number(width) or width<=0 or not Number(height) or height<=0
        or not E.NotSecret(orientation) or not E.NotSecret(reverse) then
        HidePrediction()
        return
    end
    local vertical=orientation=="VERTICAL"
    if fill.IsForbidden then
        local forbidden=fill:IsForbidden()
        if not E.NotSecret(forbidden) or forbidden then
            HidePrediction()
            return
        end
    end
    if not fill.GetNumMaskTextures or not fill.GetMaskTexture then
        HidePrediction()
        return
    end
    local count=fill:GetNumMaskTextures()
    if not Number(count) or count<0 or count>32 or count%1~=0 then
        HidePrediction()
        return
    end
    local masks={}
    for index=1,count do
        local mask=fill:GetMaskTexture(index)
        if not PublicRegion(mask) then
            HidePrediction()
            return
        end
        masks[#masks+1]=mask
    end
    local shaped=host._msufPowerShapeActive
    if not E.NotSecret(shaped) then
        HidePrediction()
        return
    end
    local shapeAsset=shaped and host._msufTexture
    if shaped and (not E.NotSecret(shapeAsset) or type(shapeAsset)~="string" or shapeAsset=="") then
        HidePrediction()
        return
    end
    if not state.prediction then
        state.prediction=PixelLayoutRegion(CreateFrame("StatusBar",nil,host))
        state.prediction:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        state.prediction:Hide()
        state.predictionFill=PixelLayoutRegion(state.prediction:GetStatusBarTexture())
        if not PublicRegion(state.predictionFill) then
            HidePrediction()
            return
        end
        state.predictionFill:SetDrawLayer("OVERLAY",3)
        state.predictionMask=PixelLayoutRegion(host:CreateMaskTexture(nil,"OVERLAY"))
        state.predictionMask:SetTexture("Interface\\Buttons\\WHITE8X8","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
        if not state.predictionFill.AddMaskTexture or not state.predictionFill.RemoveMaskTexture then
            HidePrediction()
            return
        end
        state.predictionFill:AddMaskTexture(state.predictionMask)
        state.predictionMasked=true
    end
    if not state.predictionMasked then
        HidePrediction()
        return
    end
    -- Borrow references only: shared native masks keep their owner, anchors
    -- and visibility. All hierarchy queries and binding changes stay OOC.
    local old=state.borrowedMasks or {}
    for _,mask in ipairs(old) do
        if not PublicRegion(mask) then
            HidePrediction()
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
local function Ensure(host)
    HideSamples()
    if not DetachSampleMasks() then
        state.predictionReady=false
        HidePrediction()
        return
    end
    if not state.five then
        state.five=PixelLayoutRegion(CreateFrame("StatusBar",nil,host))
        state.tick=PixelLayoutRegion(CreateFrame("StatusBar",nil,host))
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
    for _,bar in ipairs({state.five,state.tick}) do
        bar:SetParent(host)
        bar:ClearAllPoints()
    end
    state.five:SetPoint("BOTTOMLEFT",host,"TOPLEFT",0,1)
    state.five:SetPoint("BOTTOMRIGHT",host,"TOPRIGHT",0,1)
    state.five:SetHeight(3)
    state.tick:SetPoint("TOPLEFT",host,"BOTTOMLEFT",0,-1)
    state.tick:SetPoint("TOPRIGHT",host,"BOTTOMRIGHT",0,-1)
    state.tick:SetHeight(2)
    state.predictionReady=false
    EnsurePrediction(host)
end
local function Timer(bar,duration,seconds)
    if not duration or not bar.SetTimerDuration then return false end
    duration:SetTimeFromStart(GetTime(),seconds)
    bar:SetTimerDuration(duration,Enum.StatusBarInterpolation.Immediate,Enum.StatusBarTimerDirection.RemainingTime)
    bar:Show()
    return true
end
local function ObserveMana()
    if not state.ticks then
        state.last=nil
        state.maximum=nil
        return
    end
    local now=GetTime()
    local current,maximum=UnitPower("player",0),UnitPowerMax("player",0)
    if not Number(current) or not Number(maximum) then
        state.last=nil
        state.maximum=nil
        return
    end
    if state.last and state.maximum==maximum then
        if current>state.last and state.ticks then
            -- This is an observed mana gain, not a guessed server tick.
            if Timer(state.tick,state.tickDuration,2) then
                state.tickUntil=now+2
                C_Timer.After(2,ExpireTick)
            end
            state.lastGainAt=now
        end
    end
    state.last,state.maximum=current,maximum
end
local function Prediction()
    if not state.preview or not state.host or not state.hasCost then return end
    if not state.predictionReady then
        HidePrediction()
        return
    end
    local maximum=UnitPowerMax("player",0)
    local width,height=state.host:GetWidth(),state.host:GetHeight()
    local fill=state.host.GetStatusBarTexture and state.host:GetStatusBarTexture()
    if E.NotSecret(maximum) and (not Number(maximum) or maximum<=0) or not Number(width) or width~=state.width
        or not Number(height) or height~=state.height or not E.NotSecret(fill) or not fill or fill~=state.fill then
        HidePrediction()
        return
    end
    if fill.IsForbidden then
        local forbidden=fill:IsForbidden()
        if not E.NotSecret(forbidden) or forbidden then
            HidePrediction()
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
local function ManaCost(spellID,allowRestricted)
    local native=C_Spell and C_Spell.GetSpellPowerCost
    local restricted=not E.NotSecret(spellID)
    if restricted then
        -- Restricted identifiers exist on the Midnight engine only (WoW
        -- Forever included), where C_Spell accepts them.
        if not MSUF.Client.IsRetail or not native then return end
    elseif not Number(spellID) then return end
    local costs
    if native then costs=native(spellID)
    elseif GetSpellPowerCost then costs=GetSpellPowerCost(spellID) end
    if not E.NotSecret(costs) or type(costs)~="table" or canaccesstable and not canaccesstable(costs) then return end
    for _,cost in pairs(costs) do
        if E.NotSecret(cost) and type(cost)=="table" and (not canaccesstable or canaccesstable(cost))
            and Number(cost.type) and cost.type==0 then
            local value=cost.cost
            if not E.NotSecret(value) then
                if allowRestricted then return value,true end
            elseif Number(value) and value>=0 then return value,true end
        end
    end
end
local function CastCost(spellID)
    if not state.preview then return end
    HidePrediction()
    state.cost,state.hasCost=ManaCost(spellID,true)
    Prediction()
end
local function OnEvent(self,event,unit,powerToken,spellID)
    if unit~="player" or state.suspended then return end
    if event=="UNIT_SPELLCAST_SUCCEEDED" and state.rule then
        local cost=ManaCost(spellID)
        if cost and cost>0 and Timer(state.five,state.fiveDuration,5) then
            state.fiveUntil=GetTime()+5
            C_Timer.After(5,ExpireFive)
        end
    end
    if event=="UNIT_POWER_FREQUENT" or event=="UNIT_POWER_UPDATE" then
        if powerToken and powerToken~="MANA" then return end
        ObserveMana()
    elseif event=="UNIT_MAXPOWER" then
        state.last=nil
        ObserveMana()
        Prediction()
    elseif event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
        HidePrediction()
        CastCost(spellID)
    elseif state.preview then
        -- An instant spell allowed during another cast must not clear that
        -- cast's preview. Native C_Spell accepts restricted identifiers;
        -- only a public missing/invalid cast ID falls back to the channel.
        local current=select(9,UnitCastingInfo("player"))
        if E.NotSecret(current) and not Number(current) then current=select(8,UnitChannelInfo("player")) end
        if not E.NotSecret(current) or Number(current) then CastCost(current) else HidePrediction() end
    end
end
local function Disable()
    HideSamples()
    if not (InCombatLockdown and InCombatLockdown()) then DetachSampleMasks() end
    if state.editListener and MSUF.EditModeAPI then
        MSUF.EditModeAPI.UnregisterSessionListener("MSUF.ManaExtras")
        state.editListener, state.editActive = nil, nil
    end
    events:UnregisterAllEvents()
    HideFive()
    HideTick()
    HidePrediction()
    state.last=nil
    state.maximum=nil
    state.host=nil
    if state.predictionMask then state.predictionMask:Hide() end
    if state.shapeMask then state.shapeMask:Hide() end
    if not (InCombatLockdown and InCombatLockdown()) and state.prediction then
        local retained={}
        for _,mask in ipairs(state.borrowedMasks or {}) do
            if PublicRegion(mask) then state.predictionFill:RemoveMaskTexture(mask) else retained[#retained+1]=mask end
        end
        state.borrowedMasks=retained
    end
    state.fill=nil
    state.predictionReady=false
end
-- The bar that shows Mana now: the alternative mana bar, or the Player
-- power bar while it shows Mana. false: no public owner to resolve.
local function ResolveHost()
    local player=E.GetPlayerFrame()
    if not E.NotSecret(player) then return false end
    local powerBar=player and player.targetPowerBar
    if not E.NotSecret(powerBar) then return false end
    local host=E.AM.visible and E.AM.bar or powerBar
    local primary
    if Editing() then primary=PublicRegion(powerBar) and powerBar._msufPowerType
    else primary=UnitPowerType("player") end
    local displayMana=PublicRegion(powerBar) and powerBar._msufPowerDisplayMana
    local displayed=E.NotSecret(displayMana) and displayMana==true
    if not E.AM.visible and not displayed and (not Number(primary) or primary~=0) then host=nil end
    return host
end
-- Combat: a shapeshift moved Mana to another bar (or off every bar). The
-- helper is only rebound out of combat (the lifecycle owner rebuilds it at
-- combat end); until then it hides what it drew on a bar that no longer
-- shows Mana and ignores the events.
local function PowerChanged()
    if not state.host then return end
    local suspended=ResolveHost()~=state.host
    if suspended==(state.suspended==true) then return end
    state.suspended=suspended or nil
    if suspended then
        HideFive()
        HideTick()
        HidePrediction()
    end
end
Refresh = function()
    if not Editing() then HideSamples() end
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
    local host=ResolveHost()
    if host==false then
        Disable()
        return
    end
    if not PublicRegion(host) or not (state.rule or state.ticks or state.preview) then
        Disable()
        return
    end
    Ensure(host)
    events:UnregisterAllEvents()
    local api = MSUF.EditModeAPI
    if not state.editListener and api and api.RegisterSessionListener then
        state.editListener = api.RegisterSessionListener("MSUF.ManaExtras", function(active)
            state.editActive = active
            Refresh()
        end) == true
    end
    Color(state.five,"manaRegenPauseColor",1,.65,.2)
    Color(state.tick,"manaGainPulseColor",.3,1,.7)
    if state.prediction then Color(state.prediction,"manaCostColor",.7,.7,1) end
    if not state.rule then HideFive() end
    if not state.ticks then HideTick() end
    if not state.preview then HidePrediction() end
    if state.ticks then events:RegisterUnitEvent("UNIT_POWER_FREQUENT","player") end
    if state.ticks or state.preview then events:RegisterUnitEvent("UNIT_MAXPOWER","player") end
    if state.preview then
        for _,event in ipairs({"UNIT_SPELLCAST_START","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_STOP",
            "UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_SUCCEEDED"}) do
            events:RegisterUnitEvent(event,"player")
        end
    elseif state.rule then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player")
    end
    Samples(host)
    if not Editing() then
        state.last=nil
        ObserveMana()
        Prediction()
    end
end
local function IsPending() return state.pending end
function MSUF.CPBuilders.ManaExtras(boundE)
    E = boundE
    state = {}
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    return { Refresh = Refresh, Disable = Disable, PowerChanged = PowerChanged, IsPending = IsPending }
end
