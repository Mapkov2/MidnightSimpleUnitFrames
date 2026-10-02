--- Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua
--- Frame-level aura visuals on Classic: the dispel border, overlay, debuff
--- stripe and dispel-type symbols a unit or group frame shows for its
--- debuffs, the per-lane cache they are resolved from, and the change-gated
--- frame state the Borders and GroupVisuals elements read. The cleanse
--- visuals never follow a lane's icon filters, as on Retail.
---
--- Game/<Flavor>/Auras.xml loads the unit-frame aura backend after Compile.lua
--- in this order: Buttons, Filters, FrameVisuals, Lanes, UnitFrames, Requests.
--- Each file imports the earlier ones from A3._ClassicBackend at load time.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
local Backend = type(A3) == "table" and A3._ClassicBackend
assert(Backend, "Classic aura frame visuals require Game/Classic/Auras/MSUF_Auras3_Buttons.lua")
if Backend.FrameVisuals then return end
local Compile, Buttons, Filters = A3._ClassicCompile, Backend.Buttons, Backend.Filters
local FrameVisuals = {}

local UF = MSUF.UF
local type, next, pairs = type, next, pairs
local IsSecret = _G.issecretvalue or function() return false end
local C_UnitAuras = _G.C_UnitAuras
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local WipeTable = Compile.WipeTable
local FillAuraSlots = Compile.FillAuraSlots
local PlainString = Compile.PlainString
local DirectVisualFilterForTrigger = Compile.DirectVisualFilterForTrigger
local HasSecretColor = Compile.HasSecretColor
local IsUnitToken = Compile.IsUnitToken
local BindFrameUnit = Compile.BindFrameUnit
local AuraDispelColor = Buttons.AuraDispelColor
local MatchDispelTrigger = Filters.MatchDispelTrigger
-- The Classic visuals (Visuals.lua) draw the frame-level symbols and overlay.
local renderer = A3.ClassicVisuals

local function ResetLaneVisualCache(lane)
    if not lane then return end
    local cfg = lane.config
    local visual = cfg and cfg.visual
    lane._msufA3VisualCacheReady = cfg
        and cfg.enabled == true
        and cfg.visualDirect ~= true
        and visual
        and visual.enabled == true or nil
    lane._msufA3VisualAnyDebuff = nil
    lane._msufA3VisualBorderActive = nil
    lane._msufA3VisualBorderR = nil
    lane._msufA3VisualBorderG = nil
    lane._msufA3VisualBorderB = nil
    lane._msufA3VisualBorderA = nil
    lane._msufA3VisualBorderSecret = nil
    lane._msufA3VisualBorderToken = nil
    lane._msufA3VisualOverlayActive = nil
    lane._msufA3VisualOverlayR = nil
    lane._msufA3VisualOverlayG = nil
    lane._msufA3VisualOverlayB = nil
    lane._msufA3VisualOverlayA = nil
    lane._msufA3VisualOverlaySecret = nil
    lane._msufA3VisualOverlayToken = nil
end

local function DispelVisualColor(lane, visual, unit, data)
    if visual and visual.colorMode == "TYPE" then
        local hasColor, r, g, b, a, secret = AuraDispelColor(lane.config, unit, data)
        if hasColor then return r, g, b, a, secret == true end
    end
    return visual and visual.r or 0.25, visual and visual.g or 0.75, visual and visual.b or 1, visual and visual.a or 1, false
end

local function DirectDispelVisualColor(visual, unit, data)
    if visual and visual.colorMode == "TYPE" then
        local hasColor, r, g, b, a, secret = AuraDispelColor(visual, unit, data)
        if hasColor then return r, g, b, a, secret == true end
    end
    return visual and visual.r or 0.25, visual and visual.g or 0.75, visual and visual.b or 1, visual and visual.a or 1, false
end

--- Any debuff has no native filter of its own, so lanes without a PLAYER scan
--- keep it on the lane path (Compile's directVisualEligible); an Only mine
--- lane resolves every trigger here, so Any debuff reads the first HARMFUL aura.
local function ResolveDirectDispelTriggerVisual(unit, visual, trigger)
    local filter = DirectVisualFilterForTrigger(trigger) or (trigger == "ANY_DEBUFF" and "HARMFUL" or nil)
    if not (filter and GetAuraDataByIndex and IsUnitToken(unit)) then
        return false
    end
    local data = GetAuraDataByIndex(unit, 1, filter)
    if not (data and data.auraInstanceID) then
        return false
    end
    if trigger == "DISPEL_TYPE" then
        local dispelName = PlainString(data.dispelName)
        if dispelName == nil or dispelName == "" then return false end
    end
    local token = data.auraInstanceID
    if IsSecret(token) then token = nil end
    local r, g, b, a, secret = DirectDispelVisualColor(visual, unit, data)
    return true, r, g, b, a, secret == true, token
end

local function ConsiderLaneAuraVisual(lane, unit, data)
    if not (lane and lane._msufA3VisualCacheReady == true and data) then return end
    local visual = lane.config and lane.config.visual
    if not (visual and visual.enabled == true) then return end
    if lane._msufA3VisualAnyDebuff == true
        and (visual.borderEnabled ~= true or lane._msufA3VisualBorderActive == true)
        and (visual.overlayEnabled ~= true or lane._msufA3VisualOverlayActive == true) then
        return
    end
    lane._msufA3VisualAnyDebuff = true

    local borderMatched = false
    if visual.borderEnabled == true and lane._msufA3VisualBorderActive ~= true then
        borderMatched = MatchDispelTrigger(lane, unit, data, visual.borderTrigger)
        if borderMatched then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            lane._msufA3VisualBorderActive = true
            lane._msufA3VisualBorderR, lane._msufA3VisualBorderG = r, g
            lane._msufA3VisualBorderB, lane._msufA3VisualBorderA = b, a
            lane._msufA3VisualBorderSecret = secret == true
            lane._msufA3VisualBorderToken = token
        end
    end

    if visual.overlayEnabled == true and lane._msufA3VisualOverlayActive ~= true then
        -- Sharing the border's result is valid only when the border was
        -- evaluated. The overlay inherits the border's trigger, not its
        -- enabled state (Retail compiles it as a sensor of its own).
        if visual.borderEnabled == true and visual.overlayTrigger == visual.borderTrigger then
            if lane._msufA3VisualBorderActive == true then
                lane._msufA3VisualOverlayActive = true
                lane._msufA3VisualOverlayR = lane._msufA3VisualBorderR
                lane._msufA3VisualOverlayG = lane._msufA3VisualBorderG
                lane._msufA3VisualOverlayB = lane._msufA3VisualBorderB
                lane._msufA3VisualOverlayA = lane._msufA3VisualBorderA
                lane._msufA3VisualOverlaySecret = lane._msufA3VisualBorderSecret
                lane._msufA3VisualOverlayToken = lane._msufA3VisualBorderToken
            end
        elseif MatchDispelTrigger(lane, unit, data, visual.overlayTrigger) then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            lane._msufA3VisualOverlayActive = true
            lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG = r, g
            lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA = b, a
            lane._msufA3VisualOverlaySecret = secret == true
            lane._msufA3VisualOverlayToken = token
        end
    end
end

--- Walks lane.all, never lane.active: cleanse visuals ignore the icon filters.
local function ResolveDispelTriggerVisual(lane, unit, visual, trigger)
    if not (lane and visual and trigger) then return false end
    local all = lane.all
    if not all then return false end
    for _, data in next, all do
        if data and MatchDispelTrigger(lane, unit, data, trigger) then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            return true, r, g, b, a, secret == true, token
        end
    end
    return false
end

local function UpdateDispelSymbols(frame, lane, visual, unit)
    local symbol = visual and visual.symbol
    if not (frame and symbol and symbol.enabled == true and lane and lane.all) then
        return renderer.HideDispelSymbols(frame)
    end
    -- Per-frame scratch set, wiped instead of reallocated on every
    -- visual-dirty UNIT_AURA; the renderer only reads it during this call.
    local present = WipeTable(frame._msufA3ClassicDispelPresent)
    frame._msufA3ClassicDispelPresent = present
    for _, data in pairs(lane.all) do
        local dispelName = PlainString(data and data.dispelName)
        if dispelName and dispelName ~= "" then
            local matched = symbol.trigger == "DISPEL_TYPE"
                or MatchDispelTrigger(lane, unit, data, symbol.trigger)
            if matched then present[dispelName] = true end
        end
    end
    return renderer.UpdateDispelSymbols(frame, visual, present)
end

--- Symbols resolved from the unit, for a debuff lane whose native PLAYER scan
--- never sees other casters' debuffs. The trigger picks the walked filter:
--- dispellable by me, cast by me, or every debuff (Any dispel type); only a
--- readable dispel type adds a symbol, as in the lane walk above.
local function UpdateDirectDispelSymbols(frame, visual, unit)
    local symbol = visual and visual.symbol
    if not (frame and symbol and symbol.enabled == true and IsUnitToken(unit) and GetAuraSlots and GetAuraDataBySlot) then
        return renderer.HideDispelSymbols(frame)
    end
    local trigger = symbol.trigger
    local filter = trigger == "PLAYER_CAST" and "HARMFUL|PLAYER"
        or (trigger == "BY_ME" and DirectVisualFilterForTrigger(trigger)) or "HARMFUL"
    local present = WipeTable(frame._msufA3ClassicDispelPresent)
    frame._msufA3ClassicDispelPresent = present
    local slots, count = FillAuraSlots(frame._msufA3ClassicDispelSlots, GetAuraSlots(unit, filter))
    frame._msufA3ClassicDispelSlots = slots
    for i = 2, count do
        local data = GetAuraDataBySlot(unit, slots[i])
        local dispelName = PlainString(data and data.dispelName)
        if dispelName and dispelName ~= "" then present[dispelName] = true end
    end
    return renderer.UpdateDispelSymbols(frame, visual, present)
end

local function HasActiveDebuff(lane)
    return lane and lane.active and next(lane.active) ~= nil or false
end

local function StoreLaneAuraVisualCache(lane, anyDebuff,
    borderActive, br, bg, bb, ba, borderSecret, borderToken,
    overlayActive, orr, og, ob, oa, overlaySecret, overlayToken)
    lane._msufA3VisualCacheReady = true
    lane._msufA3VisualAnyDebuff = anyDebuff == true
    lane._msufA3VisualBorderActive = borderActive == true
    lane._msufA3VisualBorderR, lane._msufA3VisualBorderG = br, bg
    lane._msufA3VisualBorderB, lane._msufA3VisualBorderA = bb, ba
    lane._msufA3VisualBorderSecret = borderSecret == true
    lane._msufA3VisualBorderToken = borderToken
    lane._msufA3VisualOverlayActive = overlayActive == true
    lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG = orr, og
    lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA = ob, oa
    lane._msufA3VisualOverlaySecret = overlaySecret == true
    lane._msufA3VisualOverlayToken = overlayToken
end

local function NotifyFrameAuraVisuals(frame)
    if not frame then return end
    if frame._msufA3DeferAuraVisualNotify == true then
        return
    end
    local active = frame._msufActiveElements
    local elements = UF and UF.elements
    local borders = active and active.Borders == true and elements and elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_A3_AURA_VISUAL", BindFrameUnit(frame))
    end
    if frame.MSUFSpec and frame.MSUFSpec.scope == "group" then
        local visuals = active and active.GroupVisuals == true and elements and elements.GroupVisuals
        if visuals and visuals.Update then
            visuals.Update(frame, "MSUF_A3_AURA_VISUAL", BindFrameUnit(frame))
        end
    end
end

local function SetFrameAuraVisualState(frame,
    borderActive, br, bg, bb, ba, borderSecret, borderToken,
    overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
    if not frame then return false end
    br, bg, bb, ba = br or 0.25, bg or 0.75, bb or 1, ba or 1
    orr, og, ob, oa = orr or br, og or bg, ob or bb, oa or ba
    borderSecret = borderSecret == true
    overlaySecret = overlaySecret == true
    local overlayRendererChanged = renderer.UpdateDispelOverlay(frame, visual, overlayActive, orr, og, ob, oa) or false
    local borderChanged = frame._msufA3DispelActive ~= borderActive
        or frame._msufA3DispelColorSecret ~= borderSecret
        or frame._msufA3DispelToken ~= borderToken
    if not borderChanged and not borderSecret then
        if HasSecretColor(frame._msufA3DispelR, frame._msufA3DispelG, frame._msufA3DispelB, frame._msufA3DispelA) then
            borderChanged = true
        else
            borderChanged = frame._msufA3DispelR ~= br
                or frame._msufA3DispelG ~= bg
                or frame._msufA3DispelB ~= bb
                or frame._msufA3DispelA ~= ba
        end
    end
    local overlayChanged = frame._msufA3DispelOverlayActive ~= overlayActive
        or frame._msufA3DispelOverlayColorSecret ~= overlaySecret
        or frame._msufA3DispelOverlayToken ~= overlayToken
    if not overlayChanged and not overlaySecret then
        if HasSecretColor(frame._msufA3DispelOverlayR, frame._msufA3DispelOverlayG, frame._msufA3DispelOverlayB, frame._msufA3DispelOverlayA) then
            overlayChanged = true
        else
            overlayChanged = frame._msufA3DispelOverlayR ~= orr
                or frame._msufA3DispelOverlayG ~= og
                or frame._msufA3DispelOverlayB ~= ob
                or frame._msufA3DispelOverlayA ~= oa
        end
    end
    local changed = borderChanged or overlayChanged
        or frame._msufA3DebuffStripeActive ~= stripeActive
        or frame._msufA3DebuffStripeR ~= (visual and visual.stripeR)
        or frame._msufA3DebuffStripeG ~= (visual and visual.stripeG)
        or frame._msufA3DebuffStripeB ~= (visual and visual.stripeB)
        or frame._msufA3DebuffStripeA ~= (visual and visual.stripeAlpha)
        or frame._msufA3DebuffStripeEdge ~= (visual and visual.stripeEdge)
        or frame._msufA3DebuffStripeHeight ~= (visual and visual.stripeHeight)
    if not changed then return overlayRendererChanged end
    frame._msufA3DispelActive = borderActive == true
    frame._msufA3DispelColorSecret = borderSecret or nil
    frame._msufA3DispelToken = borderToken
    frame._msufA3DispelR, frame._msufA3DispelG, frame._msufA3DispelB, frame._msufA3DispelA = br, bg, bb, ba
    frame._msufA3DispelOverlayActive = overlayActive == true
    frame._msufA3DispelOverlayColorSecret = overlaySecret or nil
    frame._msufA3DispelOverlayToken = overlayToken
    frame._msufA3DispelOverlayR, frame._msufA3DispelOverlayG, frame._msufA3DispelOverlayB, frame._msufA3DispelOverlayA = orr, og, ob, oa
    frame._msufA3DebuffStripeActive = stripeActive == true
    frame._msufA3DebuffStripeR = visual and visual.stripeR or nil
    frame._msufA3DebuffStripeG = visual and visual.stripeG or nil
    frame._msufA3DebuffStripeB = visual and visual.stripeB or nil
    frame._msufA3DebuffStripeA = visual and visual.stripeAlpha or nil
    frame._msufA3DebuffStripeEdge = visual and visual.stripeEdge or nil
    frame._msufA3DebuffStripeHeight = visual and visual.stripeHeight or nil
    NotifyFrameAuraVisuals(frame)
    return true
end

local function FrameHasAuraVisualState(frame)
    return frame
        and (frame._msufA3DispelActive == true
            or frame._msufA3DispelOverlayActive == true
            or frame._msufA3DebuffStripeActive == true
            or frame._msufA3DispelColorSecret == true
            or frame._msufA3DispelOverlayColorSecret == true
            or frame._msufA3DispelToken ~= nil
            or frame._msufA3DispelOverlayToken ~= nil
            or frame._msufA3ClassicDispelSymbolsActive == true)
end

local function ClearFrameAuraVisualState(frame)
    if not frame then return false end
    local symbolChanged = renderer.HideDispelSymbols(frame) or false
    if not FrameHasAuraVisualState(frame) then
        return symbolChanged
    end
    return SetFrameAuraVisualState(frame, false, nil, nil, nil, nil, false, nil, false, nil, nil, nil, nil, false, nil, false, nil)
        or symbolChanged
end

--- Bars > Show on (visual.borderShowOn, compiled only for Friendly or Enemy):
--- Friendly keeps the border on a unit the player can assist, Enemy on one it
--- cannot. An unreadable answer shows nothing, as Retail's identity owners do.
--- Callers ask only while a border would show, so Both, and a frame without a
--- matching debuff, never reach UnitCanAssist. It gates the border alone: the
--- overlay has already copied the border's result when it shares the trigger.
local function DispelBorderShowOnAllows(visual, unit)
    local showOn = visual and visual.borderShowOn
    if showOn == nil then return true end
    local unitCanAssist = _G.UnitCanAssist
    if not (type(unitCanAssist) == "function" and IsUnitToken(unit)) then return false end
    local canAssist = unitCanAssist("player", unit)
    if IsSecret(canAssist) or type(canAssist) ~= "boolean" then return false end
    if showOn == "FRIENDLY" then return canAssist end
    return not canAssist
end

local function UpdateFrameAuraVisualState(frame, state, cfg, unit)
    local visual = cfg and cfg.visual
    if not (visual and visual.enabled == true) then
        return ClearFrameAuraVisualState(frame)
    end
    local debuffLane = state and state.lanes and state.lanes.debuff
    -- The stripe alone shows the debuffs the lane's filter matches.
    local stripeActive = visual.stripeEnabled == true and HasActiveDebuff(debuffLane)
    if cfg and cfg.visualDirect == true then
        --- Symbols are on here only for a lane with a native PLAYER scan; the
        --- helper also hides a host left over from the previous config, so a
        --- symbol turned off never stays frozen on the frame.
        local directSymbolChanged = UpdateDirectDispelSymbols(frame, visual, unit)
        local borderActive, br, bg, bb, ba, borderSecret, borderToken = false
        local overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = false
        if visual.borderEnabled == true then
            borderActive, br, bg, bb, ba, borderSecret, borderToken = ResolveDirectDispelTriggerVisual(unit, visual, visual.borderTrigger)
        end
        if visual.overlayEnabled == true then
            if visual.borderEnabled == true and visual.overlayTrigger == visual.borderTrigger then
                overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = borderActive, br, bg, bb, ba, borderSecret, borderToken
            else
                overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = ResolveDirectDispelTriggerVisual(unit, visual, visual.overlayTrigger)
            end
        end
        if borderActive == true and visual.borderShowOn ~= nil then
            borderActive = DispelBorderShowOnAllows(visual, unit)
        end
        return SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken,
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
            or directSymbolChanged
    end
    local lane = debuffLane
    if not (lane and lane.config and lane.config.enabled == true) then
        return ClearFrameAuraVisualState(frame)
    end
    if lane._msufA3VisualCacheReady == true then
        local anyDebuff = lane._msufA3VisualAnyDebuff == true
        local symbolChanged = UpdateDispelSymbols(frame, lane, visual, unit)
        -- The lane cache keeps the unfiltered border; Show on applies per update.
        local borderActive = anyDebuff and lane._msufA3VisualBorderActive == true
        if borderActive and visual.borderShowOn ~= nil then
            borderActive = DispelBorderShowOnAllows(visual, unit)
        end
        return SetFrameAuraVisualState(frame,
            borderActive,
            lane._msufA3VisualBorderR, lane._msufA3VisualBorderG,
            lane._msufA3VisualBorderB, lane._msufA3VisualBorderA,
            lane._msufA3VisualBorderSecret == true, lane._msufA3VisualBorderToken,
            anyDebuff and lane._msufA3VisualOverlayActive == true,
            lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG,
            lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA,
            lane._msufA3VisualOverlaySecret == true, lane._msufA3VisualOverlayToken,
            stripeActive, visual) or symbolChanged
    end
    local anyDebuff = lane.all and next(lane.all) ~= nil or false
    local borderActive, br, bg, bb, ba, borderSecret, borderToken = false
    local overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = false
    if anyDebuff and visual.borderEnabled == true then
        borderActive, br, bg, bb, ba, borderSecret, borderToken = ResolveDispelTriggerVisual(lane, unit, visual, visual.borderTrigger)
    end
    if anyDebuff and visual.overlayEnabled == true then
        if visual.borderEnabled == true and visual.overlayTrigger == visual.borderTrigger then
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = borderActive, br, bg, bb, ba, borderSecret, borderToken
        else
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = ResolveDispelTriggerVisual(lane, unit, visual, visual.overlayTrigger)
        end
    end
    StoreLaneAuraVisualCache(lane, anyDebuff, borderActive, br, bg, bb, ba, borderSecret, borderToken,
        overlayActive, orr, og, ob, oa, overlaySecret, overlayToken)
    if borderActive == true and visual.borderShowOn ~= nil then
        borderActive = DispelBorderShowOnAllows(visual, unit)
    end
    local symbolChanged = UpdateDispelSymbols(frame, lane, visual, unit)
    return SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken,
        overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
        or symbolChanged
end

FrameVisuals.ResetLaneVisualCache = ResetLaneVisualCache
FrameVisuals.ConsiderLaneAuraVisual = ConsiderLaneAuraVisual
FrameVisuals.ClearFrameAuraVisualState = ClearFrameAuraVisualState
FrameVisuals.FrameHasAuraVisualState = FrameHasAuraVisualState
FrameVisuals.UpdateFrameAuraVisualState = UpdateFrameAuraVisualState
Backend.FrameVisuals = FrameVisuals
