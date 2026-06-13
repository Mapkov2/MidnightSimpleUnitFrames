--- MSUF_Feature_ClickProbe.lua - temporary diagnostic: attribute click spikes.
--- /msufclickprobe arms a 4s window that times every MSUF OnEvent entry point
--- (unit frames, UF driver, EventBus, group member frames) and prints the top
--- consumers. Zero cost unless armed; restores all scripts after the report.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local GetTimePreciseSec = GetTimePreciseSec or GetTime
local C_Timer = C_Timer
local EnumerateFrames = EnumerateFrames
local GetMouseFocus = GetMouseFocus
local GetMouseFoci = GetMouseFoci

local probeActive = false
local results = {}
local wrapped = {}
local deepAttrHooked = {}
local deepMode = false

local function Record(label, event, dt)
    local key = label .. " " .. tostring(event)
    local r = results[key]
    if not r then
        r = { total = 0, count = 0, max = 0 }
        results[key] = r
    end
    r.total = r.total + dt
    r.count = r.count + 1
    if dt > r.max then r.max = dt end
end

local function WrapScript(frame, script, label)
    if not frame or not script or not frame.GetScript or not frame.SetScript then return false end
    wrapped[frame] = wrapped[frame] or {}
    if wrapped[frame][script] then return false end
    local orig = frame:GetScript(script)
    if type(orig) ~= "function" then return end
    wrapped[frame][script] = orig
    frame:SetScript(script, function(self, ...)
        if not probeActive then
            return orig(self, ...)
        end
        local event = script
        if script == "OnEvent" or script == "OnAttributeChanged" then
            event = select(1, ...)
        elseif script == "OnMouseDown" or script == "OnMouseUp" then
            event = select(1, ...)
        end
        local t0 = GetTimePreciseSec()
        orig(self, ...)
        Record(label .. "." .. script, event, (GetTimePreciseSec() - t0) * 1000)
    end)
    return true
end

local function Wrap(frame, label)
    return WrapScript(frame, "OnEvent", label)
end

local function Restore()
    for frame, scripts in pairs(wrapped) do
        for script, orig in pairs(scripts) do
            frame:SetScript(script, orig)
        end
        wrapped[frame] = nil
    end
    deepMode = false
end

local function FrameLabel(frame, fallback)
    local name = frame and frame.GetName and frame:GetName()
    if name and name ~= "" then return name end
    return fallback or tostring(frame)
end

local function WrapAll()
    local UF = MSUF.UF
    if UF then
        if UF.driver then Wrap(UF.driver, "UF.driver") end
        local frames = UF.frames
        if frames then
            for unit, frame in pairs(frames) do
                Wrap(frame, "UF:" .. tostring(unit))
            end
        end
    end
    local bus = _G.MSUF_EventBus
    if bus and bus.driver then Wrap(bus.driver, "EventBus") end
    local gf = MSUF.GF or _G.MSUF_GF
    local gfFrames = gf and gf.frames
    if type(gfFrames) == "table" then
        local n = 0
        for frame in pairs(gfFrames) do
            n = n + 1
            local name = frame.GetName and frame:GetName()
            Wrap(frame, "GF:" .. (name or ("member" .. n)))
        end
    end
end

local function HookGFAttributes()
    local gf = MSUF.GF or _G.MSUF_GF
    local list = gf and gf.frameList
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local frame = list[i]
        if frame and frame.HookScript and not deepAttrHooked[frame] then
            deepAttrHooked[frame] = true
            frame:HookScript("OnAttributeChanged", function(self, name)
                if probeActive then
                    Record("GFAttr:" .. FrameLabel(self, "member" .. i), name, 0)
                end
            end)
        end
    end
end

local function WrapEnumeratedEvents()
    if type(EnumerateFrames) ~= "function" then return 0 end
    local n = 0
    local frame = EnumerateFrames()
    while frame do
        if frame.GetScript and type(frame:GetScript("OnEvent")) == "function" then
            if Wrap(frame, "Enum:" .. FrameLabel(frame)) then
                n = n + 1
            end
        end
        frame = EnumerateFrames(frame)
    end
    return n
end

local function WrapDeep()
    WrapAll()
    local enumCount = WrapEnumeratedEvents()
    HookGFAttributes()
    deepMode = true
    return enumCount
end

local function Report()
    probeActive = false
    local list = {}
    for key, r in pairs(results) do
        list[#list + 1] = { key = key, total = r.total, count = r.count, max = r.max }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    print("|cff7fd5ffMSUF ClickProbe|r results (total ms | count | worst single):")
    if #list == 0 then
        print("  no MSUF OnEvent work ran during the window -- the spike is not event-driven; tell Claude.")
    end
    for i = 1, math.min(#list, 15) do
        local e = list[i]
        print(string.format("  %.3fms | %dx | max %.3fms | %s", e.total, e.count, e.max, e.key))
    end
    Restore()
    results = {}
end

-- /msufclickprobe btn: spawns two MSUF-owned test buttons with ZERO addon
-- logic. A = full secure unit button (same templates/attributes as our live
-- frames). B = inert button. If clicking A spikes the profiler while B does
-- not, the spike is Blizzard's secure click pipeline billed to the frame
-- owner -- not addon code. If A is clean, our live frame construction adds
-- the cost and gets bisected next.
local probeButtons
local function PaintProbeButton(button, r, g, b, label)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, 0.92)
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(label)
end

local function AddProbeBars(button)
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.025, 0.72)

    local hp = CreateFrame("StatusBar", nil, button)
    hp:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    hp:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 5)
    hp:SetMinMaxValues(0, 1)
    hp:SetValue(0.86)
    hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    hp:SetStatusBarColor(0.1, 0.62, 0.14, 1)

    local power = CreateFrame("StatusBar", nil, button)
    power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -1)
    power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    power:SetMinMaxValues(0, 1)
    power:SetValue(0.7)
    power:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    power:SetStatusBarColor(0.08, 0.28, 0.85, 1)
end

local function CreateSecureProbe(name, y, unit, label, template, withBars, withTargetAction)
    local button = CreateFrame("Button", name, UIParent, template or "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
    button:SetSize(190, 34)
    button:SetPoint("CENTER", 0, y)
    if unit then
        button:SetAttribute("unit", unit)
    end
    if withTargetAction ~= false then
        button:SetAttribute("*type1", "target")
        button:SetAttribute("*type2", "togglemenu")
    end
    button:RegisterForClicks("AnyUp")
    if withBars then
        AddProbeBars(button)
        PaintProbeButton(button, 0, 0, 0, label)
    else
        PaintProbeButton(button, 0.55, 0.18, 0.18, label)
    end
    return button
end

local function ProbeUnit(index)
    if UnitExists and UnitExists("party" .. tostring(index)) then
        return "party" .. tostring(index)
    end
    if UnitExists and UnitExists("raid" .. tostring(index)) then
        return "raid" .. tostring(index)
    end
    return index == 1 and "player" or nil
end

local function ToggleProbeButtons()
    if InCombatLockdown and InCombatLockdown() then
        print("MSUF ClickProbe: leave combat first.")
        return
    end
    if probeButtons then
        local shown = probeButtons[1]:IsShown()
        for i = 1, #probeButtons do
            probeButtons[i]:SetShown(not shown)
        end
        return
    end
    local unit = ProbeUnit(1) or "player"
    local unit2 = ProbeUnit(2) or unit
    local a = CreateSecureProbe("MSUF_ProbeSecureBtn", -120, unit, "A: secure target " .. unit)
    local c = CreateSecureProbe("MSUF_ProbeSecureBarsBtn", -158, unit2, "B: bars target " .. unit2, nil, true)
    local d = CreateSecureProbe("MSUF_ProbeSecureBarsNoTargetBtn", -196, unit, "C: secure bars no target", nil, true, false)
    local e = CreateSecureProbe(
        "MSUF_ProbeSecureHandlersBtn",
        -234,
        unit,
        "D: old handlers target",
        "SecureUnitButtonTemplate,SecureHandlerStateTemplate,SecureHandlerEnterLeaveTemplate,PingableUnitFrameTemplate",
        true
    )
    local b = CreateFrame("Button", "MSUF_ProbeInertBtn", UIParent)
    b:SetSize(190, 34)
    b:SetPoint("CENTER", 0, -272)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function() end)
    PaintProbeButton(b, 0.18, 0.35, 0.55, "E: inert Lua click")
    probeButtons = { a, c, d, e, b }
    print("|cff7fd5ffMSUF ClickProbe|r buttons spawned. Test A bare secure target, B bars+target, C bars no target, D old handler templates, E inert.")
end

local probeHeader
local function StyleProbeHeaderChildren()
    if not (probeHeader and probeHeader.GetChildren) then return end
    local index = 0
    for i = 1, select("#", probeHeader:GetChildren()) do
        local child = select(i, probeHeader:GetChildren())
        if child and not child._msufProbeStyled then
            index = index + 1
            child._msufProbeStyled = true
            AddProbeBars(child)
            PaintProbeButton(child, 0, 0, 0, "H" .. index .. ": header " .. tostring(child:GetAttribute("unit") or "?"))
        end
    end
end

local function ToggleHeaderProbe()
    if InCombatLockdown and InCombatLockdown() then
        print("MSUF ClickProbe: leave combat first.")
        return
    end
    if probeHeader then
        probeHeader:SetShown(not probeHeader:IsShown())
        return
    end
    probeHeader = CreateFrame("Frame", "MSUF_ProbeGroupHeader", UIParent, "SecureGroupHeaderTemplate")
    probeHeader:SetPoint("CENTER", 0, -330)
    probeHeader:SetAttribute("template", "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
    probeHeader:SetAttribute("initial-width", 190)
    probeHeader:SetAttribute("initial-height", 34)
    probeHeader:SetAttribute("initialConfigFunction", [[
self:SetWidth(190)
self:SetHeight(34)
self:SetAttribute('*type1', 'target')
self:SetAttribute('*type2', 'togglemenu')
RegisterUnitWatch(self)
]])
    probeHeader:SetAttribute("showPlayer", true)
    probeHeader:SetAttribute("showParty", true)
    probeHeader:SetAttribute("showRaid", true)
    probeHeader:SetAttribute("point", "TOP")
    probeHeader:SetAttribute("yOffset", -38)
    probeHeader:SetAttribute("unitsPerColumn", 5)
    probeHeader:SetAttribute("maxColumns", 1)
    probeHeader:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, StyleProbeHeaderChildren)
        C_Timer.After(0.5, StyleProbeHeaderChildren)
    else
        StyleProbeHeaderChildren()
    end
    print("|cff7fd5ffMSUF ClickProbe|r header probe spawned. Click H buttons and compare to live group frames.")
end

local function ScriptFlag(frame, script)
    return frame and frame.GetScript and type(frame:GetScript(script)) == "function" and "1" or "0"
end

local function CountActiveElements(frame)
    local n = 0
    local active = frame and frame._msufActiveElements
    if type(active) == "table" then
        for key, value in pairs(active) do
            if value == true then n = n + 1 end
        end
    end
    return n
end

local function ActiveElementNames(frame)
    local active = frame and frame._msufActiveElements
    if type(active) ~= "table" then return "none" end
    local names = {}
    for key, value in pairs(active) do
        if value == true then names[#names + 1] = tostring(key) end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ",") or "none"
end

local function Bool01(value)
    return value == true and "1" or "0"
end

local function GroupSpecFlags(frame)
    local spec = frame and frame.MSUFSpec
    local group = spec and spec.group
    local status = spec and spec.status
    local pred = spec and spec.prediction
    local border = spec and spec.border
    local auras = spec and spec.auras
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local tooltipMode = general and general.unitTooltipMode or "ALWAYS"
    local hover = not (general and general.highlightEnabled == false)
    return string.format(
        "name=%s hpText=%s powerText=%s power=%s pred=%s status=%s grt=%s border=%s auras=%s range=%s target=%s focus=%s deadBg=%s dispel=%s stripe=%s hook=%s hover=%s tooltip=%s",
        Bool01(spec and spec.showName ~= false),
        Bool01(spec and spec.showHealthText ~= false),
        Bool01(spec and spec.showPowerText ~= false),
        Bool01(spec and spec.power and spec.power.enabled == true),
        Bool01(pred and pred.enabled == true),
        Bool01(status and status.enabled == true),
        Bool01(status and status.groupRuntimeEnabled == true),
        Bool01(border and border.enabled == true),
        Bool01(auras and auras.enabled == true),
        Bool01(group and group.rangeFadeEnabled == true),
        Bool01(group and group.targetIndicator == true),
        Bool01(group and group.focusIndicator == true),
        Bool01(group and group.deadBgEnabled == true),
        Bool01(group and group.dispelOverlayEnabled == true),
        Bool01(group and group.debuffStripeEnabled == true),
        Bool01(frame and frame._msufGFHooked == true),
        Bool01(hover),
        tostring(tooltipMode)
    )
end

local function CountTree(frame, depth)
    if not frame or depth > 3 then return 0, 0, 0 end
    local children, regions, shown = 0, 0, 0
    if frame.GetRegions then
        regions = select("#", frame:GetRegions())
    end
    if frame.GetChildren then
        local count = select("#", frame:GetChildren())
        children = children + count
        for i = 1, count do
            local child = select(i, frame:GetChildren())
            if child and child.IsShown and child:IsShown() then shown = shown + 1 end
            local c, r, s = CountTree(child, depth + 1)
            children = children + c
            regions = regions + r
            shown = shown + s
        end
    end
    return children, regions, shown
end

local function MouseFrame()
    if type(GetMouseFoci) == "function" then
        local foci = GetMouseFoci()
        if type(foci) == "table" then
            return foci[1]
        end
    end
    if type(GetMouseFocus) == "function" then
        return GetMouseFocus()
    end
end

local function GroupRoot(frame)
    local gf = MSUF.GF or _G.MSUF_GF
    local cur = frame
    for _ = 1, 8 do
        if not cur then return frame end
        if cur._msufIsGroupFrame == true or (gf and gf.frames and gf.frames[cur] == true) then
            return cur
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return frame
end

local function RuntimeUnitSummary(unit)
    local uf = MSUF.UF
    local frame = uf and uf.frames and uf.frames[unit]
    if not frame then
        return unit .. "=nil"
    end
    local spec = frame.MSUFSpec
    local enabled = not (spec and spec.enabled == false)
    return string.format("%s:%s/%s/%s",
        unit,
        tostring(CountActiveElements(frame)),
        enabled and "on" or "off",
        ActiveElementNames(frame))
end

local function ReportGroupDiagnostics()
    local gf = MSUF.GF or _G.MSUF_GF
    local tracked, shown, raw = 0, 0, 0
    local firstShown
    local scripts = { oe = 0, oa = 0, en = 0, lv = 0, md = 0, mu = 0, cl = 0 }
    if gf and type(gf.frameList) == "table" then
        raw = #gf.frameList
        for i = 1, raw do
            local frame = gf.frameList[i]
            if frame and gf.frames and gf.frames[frame] == true then
                tracked = tracked + 1
                if frame.IsShown and frame:IsShown() then
                    shown = shown + 1
                    firstShown = firstShown or frame
                end
                if ScriptFlag(frame, "OnEvent") == "1" then scripts.oe = scripts.oe + 1 end
                if ScriptFlag(frame, "OnAttributeChanged") == "1" then scripts.oa = scripts.oa + 1 end
                if ScriptFlag(frame, "OnEnter") == "1" then scripts.en = scripts.en + 1 end
                if ScriptFlag(frame, "OnLeave") == "1" then scripts.lv = scripts.lv + 1 end
                if ScriptFlag(frame, "OnMouseDown") == "1" then scripts.md = scripts.md + 1 end
                if ScriptFlag(frame, "OnMouseUp") == "1" then scripts.mu = scripts.mu + 1 end
                if ScriptFlag(frame, "OnClick") == "1" then scripts.cl = scripts.cl + 1 end
            end
        end
    end
    print(string.format("|cff7fd5ffMSUF GF|r tracked=%d shown=%d rawList=%d", tracked, shown, raw))
    print(string.format("|cff7fd5ffMSUF GF scripts|r OE=%d OA=%d EN=%d LV=%d MD=%d MU=%d CL=%d",
        scripts.oe, scripts.oa, scripts.en, scripts.lv, scripts.md, scripts.mu, scripts.cl))

    local frame = GroupRoot(MouseFrame()) or firstShown
    if not frame then
        print("|cff7fd5ffMSUF GF|r no mouse frame")
        return
    end
    local children, regions, shownChildren = CountTree(frame, 0)
    local name = frame.GetName and frame:GetName() or nil
    local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.unit
    print(string.format("|cff7fd5ffMSUF GF sample|r %s unit=%s shown=%s active=%d children=%d shownChildren=%d regions=%d",
        tostring(name or frame), tostring(unit), tostring(frame.IsShown and frame:IsShown()), CountActiveElements(frame), children, shownChildren, regions))
    print("|cff7fd5ffMSUF GF active|r " .. ActiveElementNames(frame))
    print("|cff7fd5ffMSUF GF flags|r " .. GroupSpecFlags(frame))
    print("|cff7fd5ffMSUF UF runtime|r "
        .. RuntimeUnitSummary("target") .. " "
        .. RuntimeUnitSummary("targettarget") .. " "
        .. RuntimeUnitSummary("focus") .. " "
        .. RuntimeUnitSummary("focustarget"))
    print("scripts OE/OA/EN/LV/MD/MU/CL = "
        .. ScriptFlag(frame, "OnEvent") .. ScriptFlag(frame, "OnAttributeChanged")
        .. ScriptFlag(frame, "OnEnter") .. ScriptFlag(frame, "OnLeave")
        .. ScriptFlag(frame, "OnMouseDown") .. ScriptFlag(frame, "OnMouseUp")
        .. ScriptFlag(frame, "OnClick"))
end

local strippedGF
local function StripGroupFrames()
    if InCombatLockdown and InCombatLockdown() then
        print("MSUF ClickProbe: leave combat first.")
        return
    end
    local gf = MSUF.GF or _G.MSUF_GF
    local uf = MSUF.UF
    local list = gf and gf.frameList
    if type(list) ~= "table" then
        print("MSUF ClickProbe: no GF frameList.")
        return
    end
    local count = 0
    for i = 1, #list do
        local frame = list[i]
        if frame and gf.frames and gf.frames[frame] == true then
            count = count + 1
            if uf and uf.DetachFrame then
                uf.DetachFrame(frame)
            end
            if frame.SetScript and uf and frame:GetScript("OnEvent") == uf.DispatchFrameEvent then
                frame:SetScript("OnEvent", nil)
            end
            if frame.UnregisterAllEvents then
                frame:UnregisterAllEvents()
            end
            if frame.RegisterForClicks then
                frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
            if frame.SetAttribute then
                frame:SetAttribute("*type1", "target")
                frame:SetAttribute("*type2", "togglemenu")
            end
            if frame.hpBar then
                frame.hpBar:ClearAllPoints()
                frame.hpBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                frame.hpBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                if frame.hpBar.SetMinMaxValues then frame.hpBar:SetMinMaxValues(0, 1) end
                if frame.hpBar.SetValue then frame.hpBar:SetValue(1) end
                if frame.hpBar.SetStatusBarColor then frame.hpBar:SetStatusBarColor(0.1, 0.62, 0.14, 1) end
                frame.hpBar:Show()
            end
            if frame.bg then frame.bg:Show() end
        end
    end
    strippedGF = true
    print("|cff7fd5ffMSUF ClickProbe|r stripped " .. tostring(count) .. " live GF frames to secure button + health bar only. Use /reload to restore.")
end

SLASH_MSUFCLICKPROBE1 = "/msufclickprobe"
SlashCmdList["MSUFCLICKPROBE"] = function(msg)
    msg = type(msg) == "string" and msg or ""
    if type(msg) == "string" and msg:find("btn") then
        ToggleProbeButtons()
        return
    end
    if type(msg) == "string" and msg:find("header") then
        ToggleHeaderProbe()
        return
    end
    if type(msg) == "string" and msg:find("stripgf") then
        StripGroupFrames()
        return
    end
    if type(msg) == "string" and msg:find("gf") then
        ReportGroupDiagnostics()
        return
    end
    if probeActive then
        print("MSUF ClickProbe: already armed.")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("MSUF ClickProbe: leave combat first (script swapping).")
        return
    end
    results = {}
    local enumCount
    if msg:find("deep") then
        enumCount = WrapDeep()
    else
        WrapAll()
    end
    probeActive = true
    if deepMode then
        print("|cff7fd5ffMSUF ClickProbe|r DEEP armed for 4 seconds (" .. tostring(enumCount or 0) .. " OnEvent frames) -- left-click group frames now.")
    else
        print("|cff7fd5ffMSUF ClickProbe|r armed for 4 seconds -- click your frames NOW (right-click player, left-click raid members).")
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(4, Report)
    else
        Report()
    end
end

-- /msufidprobe: per-element identity cost. Wraps the compiled per-frame
-- update functions on player/target/targettarget/focustarget so EVERY path
-- (events, flush phases, dependent poll ticks) is timed at element level,
-- then rebuilds the runtime visual lists so the wrappers are captured.
local ID_PROBE_KEYS = {
    "_msufUpdateLoadConditions", "_msufUpdateHealth", "_msufUpdateHealthText",
    "_msufUpdatePower", "_msufUpdatePowerText", "_msufUpdateNameText",
    "_msufUpdateInlineToT", "_msufUpdatePortrait", "_msufUpdatePrediction",
    "_msufUpdateAlpha", "_msufUpdateBorders", "_msufUpdateAuras",
    "_msufUpdateRaidMarkerIndicator", "_msufUpdateLeaderIndicator",
    "_msufUpdateLevelIndicator", "_msufUpdateRaidGroupIndicator",
    "_msufUpdateEliteIndicator", "_msufUpdateStatusTextIndicator",
    "_msufUpdateCombatIndicator", "_msufUpdateRestingIndicator",
    "_msufUpdateIncomingResIndicator", "_msufUpdatePVPIndicator",
    "_msufUpdateGroupStatusRuntime", "_msufUpdateGroupVisuals",
    "_msufUpdateRangeFade", "_msufUpdateGroupRangeFade",
}
local ID_PROBE_UNITS = { "player", "target", "targettarget", "focustarget" }
local idWrapped = {}
local idActive = false

local function IdWrapFrame(frame, label)
    if not frame then return end
    for i = 1, #ID_PROBE_KEYS do
        local key = ID_PROBE_KEYS[i]
        local fn = frame[key]
        if type(fn) == "function" then
            local slot = idWrapped[frame]
            if not slot then
                slot = {}
                idWrapped[frame] = slot
            end
            if not slot[key] then
                slot[key] = fn
                frame[key] = function(...)
                    if not idActive then return fn(...) end
                    local t0 = GetTimePreciseSec()
                    local a, b, c = fn(...)
                    local reason = select(2, ...)
                    Record(label .. "." .. key:gsub("_msufUpdate", ""), reason, (GetTimePreciseSec() - t0) * 1000)
                    return a, b, c
                end
            end
        end
    end
end

local function IdRestoreAll()
    local UFNS = MSUF.UF
    for frame, slot in pairs(idWrapped) do
        for key, fn in pairs(slot) do
            frame[key] = fn
        end
        idWrapped[frame] = nil
        if UFNS and UFNS.RebuildRuntimeStatusState then
            UFNS.RebuildRuntimeStatusState(frame)
        end
    end
end

local function IdReport()
    idActive = false
    local list = {}
    for key, r in pairs(results) do
        list[#list + 1] = { key = key, total = r.total, count = r.count, max = r.max }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    print("|cff7fd5ffMSUF IdProbe|r per-element identity cost (total ms | count | worst | element):")
    if #list == 0 then
        print("  no element work ran -- the spike is outside the identity elements; tell Claude.")
    end
    for i = 1, math.min(#list, 20) do
        local e = list[i]
        print(string.format("  %.3fms | %dx | max %.3fms | %s", e.total, e.count, e.max, e.key))
    end
    IdRestoreAll()
    results = {}
end

SLASH_MSUFIDPROBE1 = "/msufidprobe"
SlashCmdList["MSUFIDPROBE"] = function()
    if idActive then
        print("MSUF IdProbe: already armed.")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("MSUF IdProbe: leave combat first.")
        return
    end
    local UFNS = MSUF.UF
    local frames = UFNS and UFNS.frames
    if not frames then
        print("MSUF IdProbe: no UF frames.")
        return
    end
    results = {}
    for i = 1, #ID_PROBE_UNITS do
        local unit = ID_PROBE_UNITS[i]
        local frame = frames[unit]
        if frame then
            IdWrapFrame(frame, unit)
            if UFNS.RebuildRuntimeStatusState then
                UFNS.RebuildRuntimeStatusState(frame)
            end
        end
    end
    -- Also wrap every live GROUP frame so the group-aura identity path is timed
    -- (group children are keyed by frame, not unit, in GF.frames).
    local gf = MSUF.GF or _G.MSUF_GF
    local gfFrames = gf and gf.frames
    local gfCount = 0
    if type(gfFrames) == "table" then
        for frame in pairs(gfFrames) do
            if type(frame) == "table" and frame._msufActiveElements then
                gfCount = gfCount + 1
                local unit = frame.unit or ("gf" .. gfCount)
                IdWrapFrame(frame, "GF:" .. tostring(unit))
                if UFNS.RebuildRuntimeStatusState then
                    UFNS.RebuildRuntimeStatusState(frame)
                end
            end
        end
    end
    idActive = true
    print(string.format("|cff7fd5ffMSUF IdProbe|r armed 6s (%d group frames wrapped) -- click through group members NOW (different targets included).", gfCount))
    if C_Timer and C_Timer.After then
        C_Timer.After(6, IdReport)
    else
        IdReport()
    end
end

-- /msufprofpeek: reads C_AddOnProfiler (the SAME source the in-game profiler
-- shows) once per frame and reports MSUF's peak per-frame ms during a window.
-- This captures EVERYTHING billed to MSUF -- secure snippets, attribute
-- handlers, element work -- not just what function wrappers can see. Use it to
-- reconcile "probe says X but profiler shows Y".
local function ProfPeek()
    local P = _G.C_AddOnProfiler
    if not P or not P.GetAddOnMetric then
        print("|cffff5555MSUF ProfPeek|r C_AddOnProfiler unavailable on this client.")
        return
    end
    local name = "MidnightSimpleUnitFrames"
    local Enum_metric = _G.Enum and _G.Enum.AddOnProfilerMetric
    if not Enum_metric then
        print("|cffff5555MSUF ProfPeek|r Enum.AddOnProfilerMetric missing.")
        return
    end
    local peak = 0
    local samples = 0
    local lastTickPeak = 0
    local driver = CreateFrame("Frame")
    local elapsed = 0
    print("|cff7fd5ffMSUF ProfPeek|r sampling 5s -- click frames NOW. Reports MSUF peak per-frame ms from C_AddOnProfiler.")
    driver:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        samples = samples + 1
        -- per-frame "last tick" CPU time MSUF used, in ms
        local v = P.GetAddOnMetric(name, Enum_metric.RecentAverageTime)
        local lastTime = P.GetAddOnMetric(name, Enum_metric.LastTime)
        if type(lastTime) == "number" and lastTime > lastTickPeak then
            lastTickPeak = lastTime
        end
        if type(v) == "number" and v > peak then peak = v end
        if elapsed >= 5 then
            self:SetScript("OnUpdate", nil)
            print(string.format("|cff7fd5ffMSUF ProfPeek|r over %d frames: peak RecentAvg=%.3fms  peak LastTime=%.3fms", samples, peak, lastTickPeak))
            print("  (LastTime peak is the single worst frame MSUF was billed -- compare to the profiler's Peak column.)")
        end
    end)
end

SLASH_MSUFPROFPEEK1 = "/msufprofpeek"
SlashCmdList["MSUFPROFPEEK"] = function()
    ProfPeek()
end

-- /msufopprobe: times the heavy ops that fire NEAR a click but that the
-- OnEvent/element probes bracket too tightly to see (deferred flushes land on a
-- later frame; secure/apply paths aren't element fns). Wraps SetPortraitTexture
-- (global C), UF.ApplySpec, GF.ApplyButton, and the A3 deferred aura flush.
local opProbeActive = false
local opSaved = {}
local function OpWrapGlobal(name)
    local fn = _G[name]
    if type(fn) ~= "function" or opSaved["_G."..name] then return end
    opSaved["_G."..name] = fn
    _G[name] = function(...)
        if not opProbeActive then return fn(...) end
        local t0 = GetTimePreciseSec()
        local a,b,c,d = fn(...)
        Record("op:"..name, "", (GetTimePreciseSec()-t0)*1000)
        return a,b,c,d
    end
end
local function OpWrapTable(tbl, key, label)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" or opSaved[label] then return end
    local fn = tbl[key]
    opSaved[label] = { tbl = tbl, key = key, fn = fn }
    tbl[key] = function(...)
        if not opProbeActive then return fn(...) end
        local t0 = GetTimePreciseSec()
        local a,b,c,d = fn(...)
        Record("op:"..label, "", (GetTimePreciseSec()-t0)*1000)
        return a,b,c,d
    end
end
local function OpRestore()
    for label, s in pairs(opSaved) do
        if type(s) == "table" and s.tbl then
            s.tbl[s.key] = s.fn
        else
            local g = label:match("^_G%.(.+)$")
            if g then _G[g] = s end
        end
        opSaved[label] = nil
    end
end

SLASH_MSUFOPPROBE1 = "/msufopprobe"
SlashCmdList["MSUFOPPROBE"] = function()
    if opProbeActive then print("op probe already armed.") return end
    if InCombatLockdown and InCombatLockdown() then print("leave combat first.") return end
    results = {}
    local UF = MSUF.UF
    local A3 = MSUF.MSUF_Auras3
    local GF = MSUF.GF or _G.MSUF_GF
    OpWrapGlobal("SetPortraitTexture")
    OpWrapGlobal("SetPortraitTextureFromCreatureDisplayID")
    if UF then OpWrapTable(UF, "ApplySpec", "UF.ApplySpec") end
    if UF then OpWrapTable(UF, "ApplyElementToFrame", "UF.ApplyElementToFrame") end
    if GF then OpWrapTable(GF, "ApplyButton", "GF.ApplyButton") end
    if A3 then OpWrapTable(A3, "RenderFrame", "A3.RenderFrame") end
    if A3 then OpWrapTable(A3, "FlushIdentityAuraRebuilds", "A3.FlushIdentityAura") end
    opProbeActive = true
    print("|cff7fd5ffMSUF OpProbe|r armed 6s -- click 3 fresh units NOW.")
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            opProbeActive = false
            local list = {}
            for k,r in pairs(results) do list[#list+1] = {key=k,total=r.total,count=r.count,max=r.max} end
            table.sort(list, function(a,b) return a.total>b.total end)
            print("|cff7fd5ffMSUF OpProbe|r (total | count | worst):")
            if #list == 0 then print("  no wrapped op ran -- cost is elsewhere; tell Claude.") end
            for i=1,math.min(#list,15) do
                local e=list[i]
                print(string.format("  %.3fms | %dx | max %.3fms | %s", e.total, e.count, e.max, e.key))
            end
            OpRestore()
            results = {}
        end)
    else
        opProbeActive = false
        OpRestore()
    end
end

-- /msuflaneflags: prints why the target's aura lanes scan capped or full.
-- The full (uncapped) scan walks every aura on a raid-buffed unit (~0.3ms);
-- the capped scan stops at cfg.max. This shows which config flag forces full.
SLASH_MSUFLANEFLAGS1 = "/msuflaneflags"
SlashCmdList["MSUFLANEFLAGS"] = function()
    local frames = MSUF.UF and MSUF.UF.frames
    local frame = frames and frames.target
    if not frame then print("no target frame (target something).") return end
    local state = frame._msufA3State
    if not state then print("target has no aura state.") return end
    local function dump(kind)
        local lane = state.lanes and state.lanes[kind]
        local cfg = lane and lane.config
        if not cfg then print(kind..": no lane") return end
        local capped = cfg.renderEnabled and cfg.naturalOrder and cfg.max > 0
            and cfg.visibleOnlyScan and (cfg.hasFilterWork ~= true or cfg.cappedFilterScan)
        print(string.format("|cff7fd5ff%s|r capped=%s | max=%s renderEnabled=%s naturalOrder=%s visibleOnlyScan=%s hasFilterWork=%s cappedFilterScan=%s sortOrder=%s needsPlayerFlag=%s",
            kind, tostring(capped == true), tostring(cfg.max),
            tostring(cfg.renderEnabled), tostring(cfg.naturalOrder),
            tostring(cfg.visibleOnlyScan), tostring(cfg.hasFilterWork),
            tostring(cfg.cappedFilterScan), tostring(cfg.sortOrder),
            tostring(cfg.needsPlayerFlag)))
    end
    dump("buff")
    dump("debuff")
end

-- /msufrt: times the RUNTIME (post-click, deferred) layer that profpeek sees
-- but the OnEvent/element probes miss -- works with auras OFF. Wraps the
-- runtime entry points: UF.UpdateRuntime, UF.FrameRuntimeUpdate, and (if
-- present) the visual-phase runner. Reason string is recorded so we see which
-- identity pass costs.
local rtActive = false
local rtSaved = {}
local function RtWrap(tbl, key, label)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" or rtSaved[label] then return end
    local fn = tbl[key]
    rtSaved[label] = { tbl = tbl, key = key, fn = fn }
    tbl[key] = function(a1, a2, a3, a4, a5, a6)
        if not rtActive then return fn(a1, a2, a3, a4, a5, a6) end
        local reason = (label == "UF.UpdateRuntime") and a2 or a2
        local t0 = GetTimePreciseSec()
        local r1, r2, r3 = fn(a1, a2, a3, a4, a5, a6)
        Record(label, reason, (GetTimePreciseSec() - t0) * 1000)
        return r1, r2, r3
    end
end
local function RtRestore()
    for label, s in pairs(rtSaved) do s.tbl[s.key] = s.fn; rtSaved[label] = nil end
end

SLASH_MSUFRT1 = "/msufrt"
SlashCmdList["MSUFRT"] = function()
    if rtActive then print("rt probe already armed.") return end
    if InCombatLockdown and InCombatLockdown() then print("leave combat first.") return end
    results = {}
    local UF = MSUF.UF
    if not UF then print("no UF.") return end
    RtWrap(UF, "UpdateRuntime", "UF.UpdateRuntime")
    RtWrap(UF, "FrameRuntimeUpdate", "UF.FrameRuntimeUpdate")
    RtWrap(UF, "ApplySpec", "UF.ApplySpec")
    RtWrap(UF, "ApplyElementToFrame", "UF.ApplyElementToFrame")
    RtWrap(UF, "ForceUpdate", "UF.ForceUpdate")
    rtActive = true
    print("|cff7fd5ffMSUF RT|r armed 6s (auras can be OFF) -- click 3 fresh units NOW.")
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            rtActive = false
            local list = {}
            for k,r in pairs(results) do list[#list+1] = {key=k,total=r.total,count=r.count,max=r.max} end
            table.sort(list, function(a,b) return a.total>b.total end)
            print("|cff7fd5ffMSUF RT|r (total | count | worst):")
            if #list == 0 then print("  no runtime call ran -- cost is in the secure/event layer; tell Claude.") end
            for i=1,math.min(#list,15) do
                local e=list[i]
                print(string.format("  %.3fms | %dx | max %.3fms | %s [%s]", e.total, e.count, e.max, e.key, tostring(e.key)))
            end
            RtRestore(); results = {}
        end)
    else rtActive = false; RtRestore() end
end

-- /msufdispatch: wraps UF.DispatchFrameEvent -- the single chokepoint EVERY
-- unit event funnels through (per-frame OnEvent script AND the central
-- eventDriver both call it). Buckets by event name. This is the layer the
-- OnEvent probe missed (it only wrapped UF.driver + per-unit frames, not the
-- central event driver). Works auras off. Reports per-event total/max so the
-- post-click UNIT_* burst names itself.
local dispActive = false
local dispSaved
SLASH_MSUFDISPATCH1 = "/msufdispatch"
SlashCmdList["MSUFDISPATCH"] = function()
    if dispActive then print("dispatch probe already armed.") return end
    if InCombatLockdown and InCombatLockdown() then print("leave combat first.") return end
    local UF = MSUF.UF
    if not (UF and type(UF.DispatchFrameEvent) == "function") then print("no DispatchFrameEvent.") return end
    results = {}
    dispSaved = UF.DispatchFrameEvent
    local orig = dispSaved
    UF.DispatchFrameEvent = function(frame, event, unit, ...)
        if not dispActive then return orig(frame, event, unit, ...) end
        local t0 = GetTimePreciseSec()
        orig(frame, event, unit, ...)
        local fu = frame and frame.unit or "?"
        Record("disp:" .. tostring(fu), event, (GetTimePreciseSec() - t0) * 1000)
    end
    -- re-point any per-frame OnEvent scripts that captured the old function
    if UF.frames then
        for _, f in pairs(UF.frames) do
            if f.GetScript and f:GetScript("OnEvent") == orig then
                f:SetScript("OnEvent", UF.DispatchFrameEvent)
            end
        end
    end
    dispActive = true
    print("|cff7fd5ffMSUF Dispatch|r armed 6s -- click 3 fresh units NOW (auras off ok).")
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            dispActive = false
            -- restore
            local cur = UF.DispatchFrameEvent
            UF.DispatchFrameEvent = dispSaved
            if UF.frames then
                for _, f in pairs(UF.frames) do
                    if f.GetScript and f:GetScript("OnEvent") == cur then
                        f:SetScript("OnEvent", dispSaved)
                    end
                end
            end
            local list = {}
            for k,r in pairs(results) do list[#list+1] = {key=k,total=r.total,count=r.count,max=r.max} end
            table.sort(list, function(a,b) return a.total>b.total end)
            print("|cff7fd5ffMSUF Dispatch|r per (frameUnit, event) (total | count | worst):")
            if #list == 0 then print("  no dispatch ran -- cost is NOT event dispatch; tell Claude.") end
            for i=1,math.min(#list,18) do
                local e=list[i]
                print(string.format("  %.3fms | %dx | max %.3fms | %s", e.total, e.count, e.max, e.key))
            end
            results = {}
        end)
    else
        dispActive = false
        UF.DispatchFrameEvent = dispSaved
    end
end

-- /msufvs: side-by-side per-frame profiler peak for MSUF vs UnhaltedUnitFrames
-- (and oUF if separate), sampled from C_AddOnProfiler every frame. Click MSUF
-- frames, then UUF frames, in the SAME window. If UUF spikes the same on its
-- own frames, the cost is the shared secure pipeline. If UUF stays flat while
-- MSUF spikes, MSUF has a real defect and this proves it.
SLASH_MSUFVS1 = "/msufvs"
SlashCmdList["MSUFVS"] = function()
    local P = _G.C_AddOnProfiler
    local Enum_metric = _G.Enum and _G.Enum.AddOnProfilerMetric
    if not (P and P.GetAddOnMetric and Enum_metric) then
        print("|cffff5555MSUF VS|r C_AddOnProfiler unavailable.")
        return
    end
    -- discover loaded addon names to compare against
    local names = { "MidnightSimpleUnitFrames" }
    local candidates = { "UnhaltedUnitFrames", "oUF", "UnhaltedUnitFrames_Options" }
    local C_AddOns = _G.C_AddOns
    for _, n in ipairs(candidates) do
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(n)
        if loaded == nil and _G.IsAddOnLoaded then loaded = _G.IsAddOnLoaded(n) end
        if loaded then names[#names + 1] = n end
    end
    local peak = {}
    for _, n in ipairs(names) do peak[n] = 0 end
    local driver = CreateFrame("Frame")
    local elapsed = 0
    print("|cff7fd5ffMSUF VS|r 8s -- click MSUF frames for 4s, then UUF frames for 4s. Comparing: " .. table.concat(names, ", "))
    driver:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        for _, n in ipairs(names) do
            local v = P.GetAddOnMetric(n, Enum_metric.LastTime)
            if type(v) == "number" and v > peak[n] then peak[n] = v end
        end
        if elapsed >= 8 then
            self:SetScript("OnUpdate", nil)
            print("|cff7fd5ffMSUF VS|r peak per-frame ms (worst single frame each addon was billed):")
            for _, n in ipairs(names) do
                print(string.format("  %.3fms | %s", peak[n], n))
            end
            print("  If UUF/oUF peak ~= MSUF peak after clicking their frames, it's the shared secure pipeline.")
            print("  If they stayed near 0 while MSUF spiked, MSUF has a real defect.")
        end
    end)
end

-- /msufgfclick: times the GROUP-CHILD attribute path that fires when the secure
-- header touches a child's unit on click. Wraps GF.ApplyButton + the global
-- UF.OnUnitChanged, and counts OnAttributeChanged fires on live group children.
-- This is the group-only path no prior probe timed.
local gfClickActive = false
local gfSaved = {}
local function GfWrap(tbl, key, label)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" or gfSaved[label] then return end
    local fn = tbl[key]
    gfSaved[label] = { tbl = tbl, key = key, fn = fn }
    tbl[key] = function(...)
        if not gfClickActive then return fn(...) end
        local t0 = GetTimePreciseSec()
        local a,b,c = fn(...)
        Record("gf:"..label, "", (GetTimePreciseSec()-t0)*1000)
        return a,b,c
    end
end
local function GfRestore()
    for label, s in pairs(gfSaved) do s.tbl[s.key] = s.fn; gfSaved[label] = nil end
end
SLASH_MSUFGFCLICK1 = "/msufgfclick"
SlashCmdList["MSUFGFCLICK"] = function()
    if gfClickActive then print("gfclick probe already armed.") return end
    if InCombatLockdown and InCombatLockdown() then print("leave combat first.") return end
    local UF = MSUF.UF
    local GF = MSUF.GF or _G.MSUF_GF
    results = {}
    if GF then GfWrap(GF, "ApplyButton", "GF.ApplyButton") end
    if GF then GfWrap(GF, "CompileSpec", "GF.CompileSpec") end
    if UF then GfWrap(UF, "OnUnitChanged", "UF.OnUnitChanged") end
    if UF then GfWrap(UF, "SetFrameSpec", "UF.SetFrameSpec") end
    if UF then GfWrap(UF, "ApplySpec", "UF.ApplySpec") end
    -- count + time OnAttributeChanged on live group children
    local list = GF and GF.frameList
    if type(list) == "table" then
        for i = 1, #list do
            local f = list[i]
            if f and f.HookScript and not gfSaved["attr"..i] then
                gfSaved["attr"..i] = false
                f:HookScript("OnAttributeChanged", function(self, name)
                    if gfClickActive and name == "unit" then
                        Record("gf:OnAttributeChanged(unit)", "", 0)
                    end
                end)
            end
        end
    end
    gfClickActive = true
    print("|cff7fd5ffMSUF GFClick|r armed 6s -- click 3 different GROUP members NOW.")
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            gfClickActive = false
            local out = {}
            for k,r in pairs(results) do out[#out+1] = {key=k,total=r.total,count=r.count,max=r.max} end
            table.sort(out, function(a,b) return a.total>b.total end)
            print("|cff7fd5ffMSUF GFClick|r (total | count | worst):")
            if #out == 0 then print("  no group-child path ran on click -- cost is the secure target action (Blizzard floor).") end
            for i=1,math.min(#out,15) do
                local e=out[i]
                print(string.format("  %.3fms | %dx | max %.3fms | %s", e.total, e.count, e.max, e.key))
            end
            GfRestore(); results = {}
        end)
    else gfClickActive = false; GfRestore() end
end
