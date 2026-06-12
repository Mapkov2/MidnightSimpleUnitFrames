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
