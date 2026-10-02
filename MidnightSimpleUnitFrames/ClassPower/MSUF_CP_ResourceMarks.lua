-- User resource marks and threshold colours.
-- Marks sit on an overlay above the bar (and above class resource pips), placed
-- along the bar's own fill axis. Threshold colours come from a native step
-- curve: a restricted percentage is evaluated inside UnitPowerPercent and the
-- resulting colour goes straight to the bar; only plain values reach Lua.
local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "ClassPower/MSUF_CP_ResourceMarks.lua")
MSUF.CPBuilders = MSUF.CPBuilders or {}

-- Class resource pips draw one level above their container and its outline
-- three levels above; marks go over both.
local OVERLAY_LEVEL = 4

-- Bound by MSUF.CPBuilders.ResourceMarks: its options table and the state
-- of the one helper the resource-extras lifecycle builds per session.
local E
local views, active, overlays
local events
local SIGNED
local pending
local function Number(v) return E.NotSecret(v) and type(v) == "number" and v == v end

-- A plain percentage through the curve, or through the rules on a client
-- without curves.
local function EvaluatePlain(view, percent)
    if view.curve then return view.curve:EvaluateUnpacked(percent) end
    local r, g, b = view.r, view.g, view.b
    for _, rule in ipairs(view.rules) do
        if rule.threshold and ((rule.direction == "BELOW" and percent < rule.fraction)
            or (rule.direction ~= "BELOW" and percent >= rule.fraction)) then
            r, g, b = rule.color[1], rule.color[2], rule.color[3]
        end
    end
    return r, g, b
end
local function Paint(view)
    if not view.enabled or not view.hasThreshold or view.suspended or view.writing then return end
    local r, g, b
    if view.classResource and E.ClassPowerReader then
        -- Client-owned resources (combo points on the target, vehicles)
        -- are never restricted where a provider exists; skip otherwise.
        local value, maximum = E.ClassPowerReader(view.unit, view.power), UnitPowerMax(view.unit, view.power)
        if not (Number(value) and Number(maximum) and maximum > 0) then return end
        r, g, b = EvaluatePlain(view, value / maximum)
    elseif view.curve and UnitPowerPercent then
        -- A plain percent evaluates without an allocation; only a restricted
        -- (secret) percent needs the client to evaluate the curve natively.
        local percent = UnitPowerPercent(view.unit, view.power, false)
        if Number(percent) then
            r, g, b = view.curve:EvaluateUnpacked(percent)
        else
            local color = UnitPowerPercent(view.unit, view.power, false, view.curve)
            if not (color and color.GetRGB) then return end
            r, g, b = color:GetRGB()
        end
    else
        local value, maximum = UnitPower(view.unit, view.power), UnitPowerMax(view.unit, view.power)
        if not (Number(value) and Number(maximum) and maximum > 0) then return end
        r, g, b = EvaluatePlain(view, value / maximum)
    end
    view.writing = true
    view.bar:SetStatusBarColor(r, g, b, view.a)
    view.writing = false
end
local function UpdateCurve(view)
    if not view.curve then return end
    view.curve:ClearPoints()
    for _, point in ipairs(view.points) do
        if point.base then point.color:SetRGBA(view.r, view.g, view.b, view.a)
        else point.color:SetRGBA(point.r, point.g, point.b, view.a) end
        view.curve:AddPoint(point.fraction, point.color)
    end
end
local function Compile(view)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then
        view.curve = nil
        return
    end
    local boundaries = { 0, 1 }
    for _, rule in ipairs(view.rules) do
        if rule.threshold then boundaries[#boundaries + 1] = rule.fraction end
    end
    table.sort(boundaries)
    local curve = view.curve or C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    view.points = {}
    local previous
    for _, fraction in ipairs(boundaries) do
        if fraction ~= previous then
            local r, g, b = view.r or 1, view.g or 1, view.b or 1
            local base = true
            for _, rule in ipairs(view.rules) do
                if rule.threshold and ((rule.direction == "BELOW" and fraction < rule.fraction)
                    or (rule.direction ~= "BELOW" and fraction >= rule.fraction)) then
                    local color = rule.color
                    r, g, b = color[1], color[2], color[3]
                    base = false
                end
            end
            view.points[#view.points + 1] = { fraction = fraction, color = CreateColor(r, g, b, view.a), base = base, r = r, g = g, b = b }
            previous = fraction
        end
    end
    view.curve = curve
    UpdateCurve(view)
end
local function View(bar)
    local view = views[bar]
    if view then return view end
    view = { bar = bar, rules = {} }
    views[bar] = view
    view.r, view.g, view.b, view.a = bar:GetStatusBarColor()
    if not Number(view.r) or not Number(view.g) or not Number(view.b) then view.r, view.g, view.b = 1, 1, 1 end
    if not Number(view.a) then view.a = 1 end
    -- The bar's owner keeps painting its base colour; follow it.
    hooksecurefunc(bar, "SetStatusBarColor", function(_, r, g, b, a)
        if view.writing or not Number(r) or not Number(g) or not Number(b) then return end
        if not Number(a) then a = 1 end
        if view.r ~= r or view.g ~= g or view.b ~= b or view.a ~= a then
            view.r, view.g, view.b, view.a = r, g, b, a
            if view.enabled and view.hasThreshold then UpdateCurve(view) end
        end
        if view.enabled then Paint(view) end
    end)
    return view
end
local function RestoreColor(view)
    if view.r then
        view.writing = true
        view.bar:SetStatusBarColor(view.r, view.g, view.b, view.a)
        view.writing = false
    end
end
local function HideMarks(overlay, from)
    for index = from or 1, #overlay.marks do overlay.marks[index]:Hide() end
end
local function Disable()
    events:UnregisterAllEvents()
    pending = false
    for _, view in pairs(views) do
        local wasEnabled = view.enabled
        view.enabled, view.hasThreshold, view.suspended = false, false, nil
        if wasEnabled then RestoreColor(view) end
    end
    for _, overlay in pairs(overlays) do
        overlay.used = nil
        HideMarks(overlay)
    end
    wipe(active)
end
-- One overlay per host, above its pips; a host resize moves the marks, so
-- the lifecycle owner refreshes them (out of combat).
local function Overlay(host)
    local overlay = overlays[host]
    if not overlay then
        overlay = PixelLayoutRegion(CreateFrame("Frame", nil, host))
        overlay:SetAllPoints(host)
        if overlay.EnableMouse then overlay:EnableMouse(false) end
        overlay.marks = {}
        overlays[host] = overlay
        if host.HookScript then
            host:HookScript("OnSizeChanged", function()
                if overlay.used and E.RequestRefresh then E.RequestRefresh() end
            end)
        end
    end
    overlay:SetFrameLevel(host:GetFrameLevel() + OVERLAY_LEVEL)
    return overlay
end
-- Fill axis of a host: a vertical bar fills upward, reverse fill starts at
-- the far edge, and the signed Balance bar runs from -max to +max.
local function Axis(rule, host)
    if rule.target == "CLASS" then
        return false, E.db.bars.classPowerFillReverse == true, SIGNED ~= nil and E.CP.renderMode == SIGNED
    end
    local orientation = host.GetOrientation and host:GetOrientation() or "HORIZONTAL"
    local reverse = host.GetReverseFill and host:GetReverseFill() or false
    if not E.NotSecret(orientation) or not E.NotSecret(reverse) then return nil end
    return orientation == "VERTICAL", reverse == true, false
end
local function Place(texture, overlay, host, vertical, reverse, fraction, size)
    local length
    if vertical then length = host:GetHeight() else length = host:GetWidth() end
    if not Number(length) or length <= 0 then return false end
    local offset = length * fraction
    texture:ClearAllPoints()
    if vertical then
        local edge, y = reverse and "TOP" or "BOTTOM", reverse and -offset or offset
        texture:SetPoint("LEFT", overlay, edge .. "LEFT", 0, y)
        texture:SetPoint("RIGHT", overlay, edge .. "RIGHT", 0, y)
        texture:SetHeight(size)
    else
        local edge, x = reverse and "RIGHT" or "LEFT", reverse and -offset or offset
        texture:SetPoint("TOP", overlay, "TOP" .. edge, x, 0)
        texture:SetPoint("BOTTOM", overlay, "BOTTOM" .. edge, x, 0)
        texture:SetWidth(size)
    end
    return true
end
-- What the Player power bar currently shows.
local function DisplayedPower(bar)
    local power, token = UnitPowerType("player")
    if bar._msufPowerDisplayMana then power, token = 0, "MANA" end
    return power, token
end
local function Target(rule)
    local player = E.GetPlayerFrame()
    if rule.target == "CLASS" then
        if E.CP.isAuraPower or not E.CP.visible or type(E.CP.powerType) ~= "number" or not E.CP.bars[1] then return end
        return E.CP.container, E.CP.powerType, E.CP.powerToken, E.CP.bars
    elseif rule.target == "ALTMANA" then
        if E.AM.visible then return E.AM.bar, 0, "MANA" end
    elseif player and player.targetPowerBar and not E.CP.augCompositeActive then
        local power, token = DisplayedPower(player.targetPowerBar)
        if Number(power) then return player.targetPowerBar, power, token end
    end
end
local function Refresh()
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    Disable()
    local rules = E.db.bars.resourceMarks or {}
    local hostCounts = {}
    local powerUnits, maxUnits = {}, {}
    local targetChanges = false
    for _, rule in ipairs(rules) do
        local host, power, token, bars = Target(rule)
        if host and rule.enabled ~= false and (not rule.resource or rule.resource == "ALL" or rule.resource == token) then
            local unit = rule.target == "CLASS" and E.ClassPowerUnit and E.ClassPowerUnit() or "player"
            local powerEvent = rule.target == "CLASS" and E.ClassPowerEvent and E.ClassPowerEvent() or "UNIT_POWER_FREQUENT"
            local maximum = UnitPowerMax(unit, power)
            local value = tonumber(rule.value) or 0
            local fraction = rule.mode == "ABSOLUTE" and Number(maximum) and maximum > 0 and value / maximum
                or rule.mode ~= "ABSOLUTE" and value / 100
            local vertical, reverse, signed = Axis(rule, host)
            if fraction and fraction >= 0 and fraction <= 1 and vertical ~= nil then
                local overlay = Overlay(host)
                local count = (hostCounts[host] or 0) + 1
                hostCounts[host] = count
                local texture = overlay.marks[count]
                if not texture then
                    texture = PixelLayoutRegion(overlay:CreateTexture(nil, "OVERLAY", nil, 7))
                    overlay.marks[count] = texture
                end
                local color = rule.color or { 1, 1, 1 }
                texture:SetColorTexture(color[1], color[2], color[3], 1)
                local size = math.max(1, math.min(20, tonumber(rule.width) or 2))
                local placed = Place(texture, overlay, host, vertical, reverse, signed and (fraction + 1) / 2 or fraction, size)
                texture:SetShown(placed and rule.mark ~= false)
                texture.rule, texture.placed = rule, placed
                overlay.used = true
                for i = 1, bars and #bars or 1 do
                    local view = View(bars and bars[i] or host)
                    if not view.enabled then
                        view.enabled = true
                        view.power = power
                        view.token = token
                        view.classResource = rule.target == "CLASS"
                        view.target, view.overlay = rule.target, overlay
                        view.unit = unit
                        view.powerEvent = powerEvent
                        maxUnits[unit] = true
                        wipe(view.rules)
                        active[#active + 1] = view
                    end
                    if rule.threshold == true then
                        view.hasThreshold = true
                        powerUnits[powerEvent] = powerUnits[powerEvent] or {}
                        powerUnits[powerEvent][unit] = true
                        if view.classResource and E.ClassNeedsTargetChanged and E.ClassNeedsTargetChanged(power) then targetChanges = true end
                    end
                    view.rules[#view.rules + 1] = { fraction = fraction, threshold = rule.threshold == true, direction = rule.direction, color = color }
                end
            end
        end
    end
    for _, view in ipairs(active) do
        if view.hasThreshold then
            Compile(view)
            Paint(view)
        end
    end
    if #active > 0 then
        local function Bind(event, units)
            if units.player and units.vehicle then events:RegisterUnitEvent(event, "player", "vehicle")
            elseif units.vehicle then events:RegisterUnitEvent(event, "vehicle")
            elseif units.player then events:RegisterUnitEvent(event, "player") end
        end
        Bind("UNIT_MAXPOWER", maxUnits)
        for event, units in pairs(powerUnits) do Bind(event, units) end
        if targetChanges then
            events:RegisterEvent("PLAYER_TARGET_CHANGED")
            if E.SupportsEvent and E.SupportsEvent("COMBO_TARGET_CHANGED") then events:RegisterEvent("COMBO_TARGET_CHANGED") end
        end
    end
end
-- Combat: a shapeshift changes what the Player power bar shows, but marks
-- and curves may only be rebuilt out of combat. Hide the marks and stop the
-- threshold colours of a bar that no longer shows their power type; show
-- them again when it does. The full rebuild follows at combat end.
local function PowerChanged()
    local player = E.GetPlayerFrame()
    local bar = player and player.targetPowerBar
    if not bar then return end
    local power = DisplayedPower(bar)
    for _, view in ipairs(active) do
        if view.target == "PLAYER" and view.bar == bar then
            local suspended = not Number(power) or power ~= view.power
            if suspended ~= (view.suspended == true) then
                view.suspended = suspended or nil
                for _, texture in ipairs(view.overlay.marks) do
                    if texture.rule and texture.rule.target == "PLAYER" then
                        texture:SetShown(not suspended and texture.rule.mark ~= false and texture.placed == true)
                    end
                end
                if suspended then RestoreColor(view) else Paint(view) end
            end
        end
    end
    pending = true
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
end
local function OnEvent(_, event, unit, token)
        if event == "PLAYER_REGEN_ENABLED" then
            events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            Refresh()
            return
        end
        if event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then
            for i = 1, #active do if active[i].classResource then Paint(active[i]) end end
            return
        end
        if not E.NotSecret(token) then return end
        for i = 1, #active do
            local view = active[i]
            if unit == view.unit and (event == "UNIT_MAXPOWER" or event == view.powerEvent)
                and (not token or not view.token or token == view.token
                or (view.classResource and E.AcceptPowerToken and E.AcceptPowerToken(view.power, token, view.token))) then
                if event == "UNIT_MAXPOWER" then
                    Refresh()
                    return
                end
                Paint(view)
            end
        end
end
local function IsPending() return pending end
function MSUF.CPBuilders.ResourceMarks(boundE)
    E = boundE
    views, active, overlays = {}, {}, {}
    events = CreateFrame("Frame")
    local constants = _G.MSUF_CP_CONST
    local modes = constants and constants.CPK and constants.CPK.MODE
    SIGNED = modes and modes.SIGNED_CONTINUOUS
    pending = false
    events:SetScript("OnEvent", OnEvent)
    return { Refresh = Refresh, Disable = Disable, PowerChanged = PowerChanged, IsPending = IsPending }
end
