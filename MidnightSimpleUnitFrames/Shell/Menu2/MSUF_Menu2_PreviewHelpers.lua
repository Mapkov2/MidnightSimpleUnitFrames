local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local F = M.Fallbacks or {}
local H = M.PreviewHelpers or {}
M.PreviewHelpers = H
local CP = M.ClassPowerPreview or {}
M.ClassPowerPreview = CP

-- Shared Menu2 preview helpers.
-- Centralizes mock class-power colors, shape helpers, and small rendering utilities used by
-- preview modules. Keep preview-only fallbacks here instead of coupling pages to live runtime.
local floor = math.floor
CP.WHITE8 = CP.WHITE8 or "Interface\\Buttons\\WHITE8X8"
CP.MEDIA = CP.MEDIA or ("Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\ClassPower\\")
function CP.ShapeTextures(prefix, axis)
    local tex = { fill = CP.MEDIA .. prefix .. "_fill.tga", bg = CP.MEDIA .. prefix .. "_bg.tga", edge = CP.MEDIA .. prefix .. "_edge.tga" }
    tex.axis = axis
    return tex
end
CP.CLASS_SHAPES = CP.CLASS_SHAPES or {
    CIRCLE = CP.ShapeTextures("pip_circle"),
    DIAMOND = CP.ShapeTextures("pip_diamond"),
    HEX = CP.ShapeTextures("pip_hex"),
}
CP.POWER_SHAPES = CP.POWER_SHAPES or {
    ROUND = CP.ShapeTextures("power_round"),
    CRYSTAL = CP.ShapeTextures("power_crystal"),
    ORB = CP.ShapeTextures("pip_circle", "VERTICAL"),
}
function CP.NormalizeClassShape(value)
    value = tostring(value or "BAR"):upper()
    return (value == "CIRCLE" or value == "DIAMOND" or value == "HEX") and value or "BAR"
end
function CP.ResolvePowerShape(value, classShape)
    value = tostring(value or "BAR"):upper()
    if value == "ROUND" or value == "CRYSTAL" or value == "ORB" or value == "BAR" then return value end
    if value == "FOLLOW_CLASS" then
        classShape = CP.NormalizeClassShape(classShape)
        if classShape == "CIRCLE" then return "ROUND" end
        if classShape == "DIAMOND" or classShape == "HEX" then return "CRYSTAL" end
    end
    return "BAR"
end
CP.FALLBACK_COLORS = CP.FALLBACK_COLORS or {
    ARCANE_CHARGES = { 0.45, 0.55, 1.00 },
    CHARGED = { 0.60, 0.20, 0.80 },
    CHI = { 0.70, 1.00, 0.86 },
    COMBO_POINTS = { 1.00, 0.82, 0.10 },
    EBON_MIGHT = { 0.40, 0.80, 0.60 },
    ESSENCE = { 0.32, 0.74, 1.00 },
    HOLY_POWER = { 0.95, 0.86, 0.20 },
    INSANITY = { 0.55, 0.32, 0.95 },
    MAELSTROM = { 0.00, 0.55, 1.00 },
    MAELSTROM_ABOVE_5 = { 1.00, 0.50, 0.00 },
    RUNES = { 0.55, 0.85, 1.00 },
    SOUL_FRAGMENTS = { 0.00, 0.80, 0.00 },
    SOUL_FRAGMENTS_META = { 0.60, 0.20, 0.93 },
    SOUL_FRAGMENTS_VENG = { 0.34, 0.06, 0.46 },
    SOUL_SHARDS = { 0.58, 0.28, 0.92 },
    STAGGER_GREEN = { 0.52, 1.00, 0.52 },
    STAGGER_YELLOW = { 1.00, 0.98, 0.72 },
    STAGGER_RED = { 1.00, 0.42, 0.42 },
    TIP_OF_THE_SPEAR = { 0.60, 0.80, 0.20 },
    WHIRLWIND = { 0.20, 0.80, 0.20 },
}
CP.COMBO_POINT_SLOT_TOKENS = CP.COMBO_POINT_SLOT_TOKENS or {
    "COMBO_POINTS_1", "COMBO_POINTS_2", "COMBO_POINTS_3", "COMBO_POINTS_4",
    "COMBO_POINTS_5", "COMBO_POINTS_6", "COMBO_POINTS_7",
}
local COMBO_POINT_RAMP_R = CP.COMBO_POINT_RAMP_R or { 0.00, 0.00, 1.00, 1.00, 1.00, 1.00, 1.00 }
local COMBO_POINT_RAMP_G = CP.COMBO_POINT_RAMP_G or { 0.95, 0.95, 1.00, 1.00, 1.00, 0.05, 0.05 }
local COMBO_POINT_RAMP_B = CP.COMBO_POINT_RAMP_B or { 1.00, 1.00, 0.00, 0.00, 0.00, 0.05, 0.05 }
CP.COMBO_POINT_RAMP_R, CP.COMBO_POINT_RAMP_G, CP.COMBO_POINT_RAMP_B = COMBO_POINT_RAMP_R, COMBO_POINT_RAMP_G, COMBO_POINT_RAMP_B
function CP.ColorOverride(tableName, token)
    local db = _G.MSUF_DB
    local general = db and db.general
    local overrides = general and general[tableName]
    local c = overrides and token and overrides[token]
    if type(c) ~= "table" then return nil end
    local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil
end
function CP.ResolveColor(token, fallbackR, fallbackG, fallbackB, powerColorFn)
    -- User overrides should show in preview, then fall back to runtime power-color helpers,
    -- and finally to fixed preview colors when the real runtime is unavailable.
    local r, g, b = CP.ColorOverride("classPowerColorOverrides", token)
    if r then return r, g, b end
    if type(_G.MSUF_GetPowerBarColor) == "function" and token then
        r, g, b = _G.MSUF_GetPowerBarColor(0, token)
        if type(r) == "number" then return r, g, b end
    end
    local pbc = _G.PowerBarColor
    local c = pbc and token and pbc[token]
    if c then
        r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
        if type(r) == "number" then return r, g, b end
    end
    c = token and CP.FALLBACK_COLORS[token]
    if c then return c[1], c[2], c[3] end
    if type(powerColorFn) == "function" and token then
        r, g, b = powerColorFn(token)
        if type(r) == "number" then return r, g, b end
    end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end
function CP.ResolveBaseColor(spec, bars, fallbackR, fallbackG, fallbackB, powerColorFn)
    if bars and bars.classPowerColorByType == false then return 1, 1, 1 end
    return CP.ResolveColor(spec and spec.token, fallbackR, fallbackG, fallbackB, powerColorFn)
end
function CP.ResolveTextColor(fallbackR, fallbackG, fallbackB, powerColorFn)
    return CP.ResolveColor("RESOURCE_TEXT", fallbackR or 1, fallbackG or 1, fallbackB or 1, powerColorFn)
end
function CP.ResolveComboColor(bars, slot, baseR, baseG, baseB)
    local mode = bars and bars.classPowerComboPointColorMode
    if mode ~= "ramp" and mode ~= "custom" then return baseR, baseG, baseB end
    slot = tonumber(slot) or 1
    if slot < 1 then slot = 1 elseif slot > 7 then slot = 7 end
    if mode == "custom" then
        local r, g, b = CP.ColorOverride("classPowerColorOverrides", CP.COMBO_POINT_SLOT_TOKENS[slot])
        if r then return r, g, b end
    end
    return COMBO_POINT_RAMP_R[slot], COMBO_POINT_RAMP_G[slot], COMBO_POINT_RAMP_B[slot]
end
function CP.IsCharged(spec, bars, slot)
    return spec and spec.token == "COMBO_POINTS"
        and bars and bars.showChargedComboPoints ~= false
        and spec.chargedSlots and spec.chargedSlots[slot] == true
end
function CP.IsSingleBarMode(mode)
    return mode == "continuous" or mode == "timer_bar" or mode == "stagger" or mode == "aura_single"
end
function CP.IsEssence(spec)
    return spec and spec.token == "ESSENCE"
end
function CP.TokenForValue(spec, value)
    if spec and spec.mode == "stagger" then
        value = tonumber(value)
        if value == nil then value = tonumber(spec.value) or 0 end
        if value >= 0.60 then return "STAGGER_RED" end
        if value > 0.30 then return "STAGGER_YELLOW" end
        return "STAGGER_GREEN"
    end
    return spec and spec.token
end
function CP.FillForSegment(spec, index, valueOverride)
    if not spec then return index <= 3 and 1 or 0 end
    local mode = spec.mode or "segmented"
    local value = tonumber(valueOverride)
    if value == nil then value = tonumber(spec.value) or 0 end
    if CP.IsSingleBarMode(mode) then
        if index ~= 1 then return 0 end
        if value < 0 then value = 0 elseif value > 1 then value = 1 end
        return value
    end
    local full = floor(value)
    if mode == "fractional" or CP.IsEssence(spec) then
        local partial = value - full
        if index <= full then return 1 end
        if index == full + 1 and partial > 0.001 then return partial end
        return 0
    end
    return index <= full and 1 or 0
end
function CP.AnimatedValue(spec, elapsed)
    if not spec then return nil end
    local mode = spec.mode or "segmented"
    local maxValue = tonumber(spec.segments) or 1
    if CP.IsSingleBarMode(mode) then maxValue = 1 elseif maxValue < 1 then maxValue = 1 end
    elapsed = tonumber(elapsed) or 0
    if mode == "timer_bar" then return 1 - ((elapsed % 4.8) / 4.8) end
    local phase = (elapsed % 2.4) / 2.4
    local wave = phase < 0.5 and (phase * 2) or ((1 - phase) * 2)
    if mode == "continuous" or mode == "stagger" or mode == "aura_single" then return 0.08 + (wave * 0.88) end
    if CP.IsEssence(spec) then
        local cycle = (elapsed / 1.15) % (maxValue + 1)
        if cycle >= maxValue then return maxValue end
        local full = floor(cycle)
        return full + (cycle - full)
    end
    if mode == "fractional" then return wave * maxValue end
    local steps = maxValue * 2
    local step = floor((elapsed / 0.42) % steps)
    if step <= maxValue then return step end
    return steps - step
end
function CP.TextForValue(spec, value)
    if not spec then return "" end
    if value == nil then return spec.previewText or "" end
    local mode = spec.mode or "segmented"
    if mode == "continuous" then return tostring(floor((value * 100) + 0.5)) .. " / 100" end
    if mode == "timer_bar" then return string.format("%.1fs", floor((value * 20 * 10) + 0.5) / 10) end
    if mode == "stagger" then return tostring(floor((value * 34) + 0.5)) .. "K" end
    if mode == "aura_single" then return tostring(floor((value * 5) + 0.5)) end
    if mode == "fractional" then return string.format("%.1f", value) end
    local rounded = CP.IsEssence(spec) and floor(value) or floor(value + 0.5)
    if spec.token == "SOUL_FRAGMENTS_VENG" then return tostring(rounded) .. " / " .. tostring(tonumber(spec.segments) or 6) end
    return tostring(rounded)
end
local RUNE_PREVIEW_REMAINING = { nil, 7.2, nil, 4.1, nil, 1.4 }
local RUNE_PREVIEW_OFFSET = { nil, 0.0, nil, 3.1, nil, 6.2 }
local RUNE_PREVIEW_READY_HOLD = 1.2
function CP.FormatSeconds(remaining)
    remaining = tonumber(remaining) or 0
    if remaining <= 0.05 then return "" end
    return string.format("%.1f", floor((remaining * 10) + 0.5) / 10)
end
function CP.FillRuneState(out, runeID, totalDuration, elapsed, animated)
    out.id = runeID
    out.total = totalDuration
    local baseRemaining = RUNE_PREVIEW_REMAINING[runeID]
    if not baseRemaining then
        out.ready = true
        out.elapsed = totalDuration
        out.remaining = 0
        return out
    end
    out.ready = false
    if animated then
        local cycle = totalDuration + RUNE_PREVIEW_READY_HOLD
        local progress = ((tonumber(elapsed) or 0) + (RUNE_PREVIEW_OFFSET[runeID] or 0)) % cycle
        if progress >= totalDuration then
            out.ready = true
            out.elapsed = totalDuration
            out.remaining = 0
        else
            out.elapsed = progress
            out.remaining = totalDuration - progress
        end
    else
        out.remaining = baseRemaining
        out.elapsed = totalDuration - baseRemaining
    end
    if out.remaining < 0.05 then
        out.ready = true
        out.elapsed = totalDuration
        out.remaining = 0
    end
    return out
end
function CP.BuildRuneOrder(scratch, bars, spec, elapsed, animated)
    local states = scratch.runeStates
    if not states then
        states = {}
        scratch.runeStates = states
    end
    local totalDuration = tonumber(spec and spec.runeDuration) or 10
    if totalDuration < 1 then totalDuration = 10 end
    for i = 1, 6 do states[i] = CP.FillRuneState(states[i] or {}, i, totalDuration, elapsed, animated) end
    for i = 7, #states do states[i] = nil end
    local sortOrder = bars and bars.runeSortOrder
    if sortOrder == "asc" then
        table.sort(states, function(a, b)
            if a.ready ~= b.ready then return a.ready == true end
            return (a.id or 0) < (b.id or 0)
        end)
    elseif sortOrder == "desc" then
        table.sort(states, function(a, b)
            if a.ready ~= b.ready then return a.ready ~= true end
            return (a.id or 0) < (b.id or 0)
        end)
    else
        table.sort(states, function(a, b) return (a.id or 0) < (b.id or 0) end)
    end
    return states
end
function CP.ResolveTexture(key, fallback)
    if key and key ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        local path = type(resolve) == "function" and resolve(key) or nil
        if path and path ~= "" then return path end
    end
    if fallback and fallback ~= "" then return fallback end
    if type(_G.MSUF_GetBarTexture) == "function" then
        local path = _G.MSUF_GetBarTexture()
        if path and path ~= "" then return path end
    end
    return CP.WHITE8
end
function H.InstallZoomPan(ZoomPan, opts)
    if type(ZoomPan) ~= "table" then return end
    opts = opts or {}
    local floor = math.floor
    local minZoom = tonumber(opts.minZoom) or 0.35
    local maxZoom = tonumber(opts.maxZoom) or 4.0
    local steps = opts.steps or { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }
    local deps = {}
    local white = "Interface\\Buttons\\WHITE8X8"
    local function PathValue(object, path)
        if not object or not path then return nil end
        if type(path) ~= "table" then return object[path] end
        local value = object
        for i = 1, #path do
            value = value and value[path[i]]
        end
        return value
    end
    local function TR(text)
        local fn = deps.TR
        return (type(fn) == "function" and fn(text)) or text
    end
    local function Round(value)
        return floor((tonumber(value) or 0) + 0.5)
    end
    local function PanKey(name)
        return tostring(opts.panPrefix or "_msufPreview") .. name
    end
    local PAN_PANNING, PAN_BOX = PanKey("Panning"), PanKey("PanBox")
    local PAN_CURSOR_X, PAN_CURSOR_Y = PanKey("PanCursorX"), PanKey("PanCursorY")
    local PAN_START_X, PAN_START_Y = PanKey("PanStartX"), PanKey("PanStartY")
    local PAN_BUTTON = PanKey("PanButton")
    ZoomPan.MIN = minZoom
    ZoomPan.MAX = maxZoom
    function ZoomPan.Configure(nextDeps)
        if opts.configureTableOnly then
            if type(nextDeps) == "table" then deps = nextDeps end
        else
            deps = nextDeps or deps or {}
        end
    end
    function ZoomPan.Clamp(value)
        value = tonumber(value) or 1
        if value < minZoom then return minZoom end
        if value > maxZoom then return maxZoom end
        return floor(value * 100 + 0.5) / 100
    end
    function ZoomPan.UpdateControls(box)
        if not box then return end
        local zoom = box._manualZoom
        local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
        local readout = box[opts.readoutField or "zoomReadout"]
        if readout then
            local pct = floor(scale * 100 + 0.5)
            readout:SetText(zoom and string.format("%d%%", pct) or string.format(opts.translateFitText and TR("Fit %d%%") or "Fit %d%%", pct))
        end
        local fitText = PathValue(box, opts.fitButtonTextPath or { "zoomFitButton", "fs" })
        if fitText then fitText:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1) end
    end
    function ZoomPan.ApplyPan(box)
        if opts.panMode == "topLeft" then
            if not (box and box._stage and box._mock) then return end
            local x = (tonumber(box._mockBaseOffsetX) or 0) + (tonumber(box._zoomPanX) or 0)
            local y = (tonumber(box._mockBaseOffsetY) or 0) + (tonumber(box._zoomPanY) or 0)
            box._mock:ClearAllPoints()
            box._mock:SetPoint("TOPLEFT", box._stage, "TOPLEFT", x, y)
            return
        end
        if not (box and box.canvas and box.mock) then return end
        local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        box.mock:ClearAllPoints()
        box.mock:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._mockBaseOffsetX) or 0) + panX, (tonumber(box._mockBaseOffsetY) or 0) + panY)
        if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
            box.mock.cast:ClearAllPoints()
            box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._detachedCastBaseOffsetX) or 0) + panX, (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
        end
    end
    function ZoomPan.SetZoom(box, zoom, reason)
        if not box then return end
        if zoom == nil or zoom == "fit" then
            box._manualZoom = nil
            box._zoomPanX, box._zoomPanY = 0, 0
        else
            box._manualZoom = ZoomPan.Clamp(zoom)
        end
        ZoomPan.UpdateControls(box)
        reason = reason or opts.defaultReason or "UNIT_PREVIEW_ZOOM"
        if type(opts.refresh) == "function" then
            opts.refresh(box, reason, deps)
        elseif box.Refresh then
            box:Refresh(reason)
        end
    end
    function ZoomPan.Step(box, direction)
        if not box then return end
        local current = ZoomPan.Clamp(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
        local nextZoom = current
        if (tonumber(direction) or 0) > 0 then
            for i = 1, #steps do
                if steps[i] > current + 0.001 then
                    nextZoom = steps[i]
                    break
                end
            end
        else
            for i = #steps, 1, -1 do
                if steps[i] < current - 0.001 then
                    nextZoom = steps[i]
                    break
                end
            end
        end
        ZoomPan.SetZoom(box, nextZoom, opts.stepReason or "UNIT_PREVIEW_ZOOM_STEP")
    end
    function ZoomPan.Stop(surface)
        if not surface then return end
        local box = surface[PAN_BOX]
        surface[PAN_PANNING], surface[PAN_BOX], surface[PAN_BUTTON] = nil, nil, nil
        surface[PAN_CURSOR_X], surface[PAN_CURSOR_Y] = nil, nil
        surface[PAN_START_X], surface[PAN_START_Y] = nil, nil
        surface:SetScript("OnUpdate", nil)
        local update = deps[opts.updateHintKey or "UpdateHandleHint"]
        if box and type(update) == "function" then update(box, box._selectedHandle) end
    end
    function ZoomPan.Start(surface, box, button)
        if not (surface and box) then return false end
        if surface[PAN_PANNING] then return true end
        local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
        if not (ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
        if not box._manualZoom then
            box._manualZoom = ZoomPan.Clamp(box._mockScale or box._mockAutoScale or 1)
            ZoomPan.UpdateControls(box)
        end
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        surface[PAN_PANNING], surface[PAN_BOX] = true, box
        surface[PAN_BUTTON] = button
        surface[PAN_CURSOR_X], surface[PAN_CURSOR_Y] = (cx or 0) / uiScale, (cy or 0) / uiScale
        surface[PAN_START_X], surface[PAN_START_Y] = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        local hint = box[opts.hintField or "hint"]
        if hint then hint:SetText(TR("moving preview canvas - release mouse to stop - Fit recenters")) end
        surface:SetScript("OnUpdate", function(self)
            if not self[PAN_PANNING] then return end
            if IsMouseButtonDown and self[PAN_BUTTON] and not IsMouseButtonDown(self[PAN_BUTTON]) then
                ZoomPan.Stop(self)
                return
            end
            local mx, my = GetCursorPosition()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            local nextX = Round((self[PAN_START_X] or 0) + ((mx or 0) / scale - (self[PAN_CURSOR_X] or 0)))
            local nextY = Round((self[PAN_START_Y] or 0) + ((my or 0) / scale - (self[PAN_CURSOR_Y] or 0)))
            if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
                box._zoomPanX, box._zoomPanY = nextX, nextY
                ZoomPan.ApplyPan(box)
            end
        end)
        return true
    end
    function ZoomPan.CreateButton(parent, text, width, tooltip, onClick)
        local T = deps.T
        local template = opts.themeButton and (T and T.Template and T.Template() or nil) or (opts.buttonTemplate or "BackdropTemplate")
        local btn = CreateFrame("Button", nil, parent, template)
        local tex = deps[opts.buttonTextureKey or "TEX_W8"] or white
        btn:SetSize(width or 24, 18)
        btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
        btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
        btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
        local fontField = opts.buttonFontField or "fs"
        if opts.themeButton and T and T.Font then
            btn[fontField] = T.Font(btn, "GameFontDisableSmall", text, { 0.78, 0.84, 0.96, 1 })
        elseif not opts.themeButton then
            btn[fontField] = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn[fontField]:SetText(text)
            btn[fontField]:SetTextColor(0.78, 0.84, 0.96, 1)
        end
        if btn[fontField] then btn[fontField]:SetPoint("CENTER") end
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.05, 0.07, 0.11, 0.98)
            self:SetBackdropBorderColor(0.28, 0.42, 0.68, 1)
            if GameTooltip and tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(TR(tooltip), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
            self:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
            if GameTooltip then GameTooltip:Hide() end
        end)
        return btn
    end
end
function H.BuildZoomBar(box, surface, opts)
    if not (box and surface) then return nil end
    opts = opts or {}
    local tr = opts.Tr or F.Identity
    local tex = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local template = opts.template or "BackdropTemplate"
    local stepZoom = opts.StepZoom or F.Noop
    local setZoom = opts.SetZoom or F.Noop
    local startPan = opts.StartPan or F.False
    local stopPan = opts.StopPan or F.Noop
    local createButton = opts.CreateZoomButton or function(parent, text, width, tooltip, onClick)
        local btn = CreateFrame("Button", nil, parent, template)
        btn:SetSize(width or 24, 18)
        btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end
    local prefix = opts.fieldPrefix or ""
    local zoomBar = CreateFrame("Frame", nil, surface, template)
    zoomBar:SetSize(opts.width or 160, opts.height or 22)
    zoomBar:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -8, -6)
    zoomBar:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
    zoomBar:SetBackdropColor(0.015, 0.018, 0.030, 0.86)
    zoomBar:SetBackdropBorderColor(0.10, 0.14, 0.22, 0.92)
    if zoomBar.SetFrameLevel then zoomBar:SetFrameLevel((surface.GetFrameLevel and surface:GetFrameLevel() or 0) + 80) end
    zoomBar:EnableMouse(true)
    zoomBar:EnableMouseWheel(true)
    if zoomBar.SetPropagateMouseWheel then zoomBar:SetPropagateMouseWheel(false) end
    box[prefix .. "zoomBar"] = zoomBar
    local function AddZoomButton(field, text, width, tooltip, onClick, relativeTo, offset)
        local btn = createButton(zoomBar, text, width, tooltip, onClick)
        if relativeTo then
            btn:SetPoint("LEFT", relativeTo, "RIGHT", offset or 3, 0)
        else
            btn:SetPoint("LEFT", zoomBar, "LEFT", offset or 3, 0)
        end
        box[prefix .. field] = btn
        return btn
    end
    zoomBar:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr("Preview zoom"), 1, 1, 1)
            GameTooltip:AddLine(tr("Use the buttons or Ctrl + mouse wheel to zoom."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(tr("Ctrl + left-drag moves the preview canvas. Fit recenters it."), 0.55, 0.68, 0.86, true)
            GameTooltip:Show()
        end
    end)
    zoomBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    local zoomOut = AddZoomButton("zoomOutButton", "-", 18, "Zoom out", function() stepZoom(box, -1) end)
    local T = opts.T
    local readout
    if opts.themeReadout and T and T.Font then
        readout = T.Font(zoomBar, "GameFontDisableSmall", "", { 0.72, 0.78, 0.90, 1 })
    else
        readout = zoomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        readout:SetTextColor(0.72, 0.78, 0.90, 1)
    end
    readout:SetPoint("LEFT", zoomOut, "RIGHT", 3, 0)
    readout:SetSize(54, 18)
    readout:SetJustifyH("CENTER")
    box[prefix .. "zoomReadout"] = readout
    local fitButton = AddZoomButton("zoomFitButton", "Fit", 28, "Fit preview", function() setZoom(box, nil, opts.fitReason) end, readout)
    local oneButton = AddZoomButton("zoomOneButton", "1:1", 30, "Pixel preview", function() setZoom(box, 1, opts.oneReason) end, fitButton)
    AddZoomButton("zoomInButton", "+", 18, "Zoom in", function() stepZoom(box, 1) end, oneButton)
    local function ZoomWheel(self, delta)
        local dir = (delta or 0) > 0 and 1 or -1
        if IsControlKeyDown and IsControlKeyDown() then
            if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
            stepZoom(box, dir)
        elseif self.SetPropagateMouseWheel then
            self:SetPropagateMouseWheel(true)
        end
    end
    if opts.wheelField then box[opts.wheelField] = ZoomWheel end
    surface:SetScript("OnMouseWheel", ZoomWheel)
    zoomBar:SetScript("OnMouseWheel", function(_, delta) stepZoom(box, (delta or 0) > 0 and 1 or -1) end)
    if surface.RegisterForDrag then surface:RegisterForDrag("LeftButton") end
    surface:SetScript("OnMouseDown", function(self, button) startPan(self, box, button) end)
    surface:SetScript("OnMouseUp", stopPan)
    surface:SetScript("OnDragStart", function(self, button) startPan(self, box, button) end)
    surface:SetScript("OnDragStop", stopPan)
    surface:SetScript("OnHide", stopPan)
    return zoomBar, ZoomWheel
end
function H.IsTextInputFocused()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end
function H.KeyDelta(key)
    if key == "LEFT" then return -1, 0 end
    if key == "RIGHT" then return 1, 0 end
    if key == "UP" then return 0, 1 end
    if key == "DOWN" then return 0, -1 end
    return nil, nil
end
function H.NudgeStep(opts)
    opts = opts or {}
    if IsControlKeyDown and IsControlKeyDown() then return tonumber(opts.ctrlStep) or 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return tonumber(opts.shiftStep) or 5 end
    return tonumber(opts.step) or 1
end
function H.ShouldSkipDuplicateNudge(owner, dx, dy, opts)
    if not owner then return false end
    opts = opts or {}
    local now = GetTime and GetTime() or 0
    if now <= 0 then return false end
    local sigKey = opts.sigKey or "_msufLastNudgeSig"
    local atKey = opts.atKey or "_msufLastNudgeAt"
    local sig = tostring(dx or 0) .. ":" .. tostring(dy or 0)
    if owner[sigKey] == sig and (now - (owner[atKey] or 0)) < (tonumber(opts.window) or 0.02) then return true end
    owner[sigKey] = sig
    owner[atKey] = now
    return false
end
local function SetKeyboardPropagate(frame, propagate)
    if frame and frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(propagate == true) end
end
function H.FocusKeyboardTarget(owner, handle, defer, opts)
    if not owner then return end
    opts = opts or {}
    local selectedField = opts.selectedField or "_selectedHandle"
    handle = handle or (selectedField and owner[selectedField])
    if owner.EnableKeyboard then owner:EnableKeyboard(true) end
    SetKeyboardPropagate(owner, handle and false or true)
    if handle and handle.EnableKeyboard then handle:EnableKeyboard(true) end
    SetKeyboardPropagate(handle, false)
    if handle and handle.SetFocus then
        handle:SetFocus()
    elseif owner.SetFocus then
        owner:SetFocus()
    end
    if defer then
        local selected = handle
        _G.C_Timer.After(0, function()
            if not (owner and owner.IsShown and owner:IsShown()) then return end
            if selected and selected.IsShown and not selected:IsShown() then return end
            if selected and selectedField and owner[selectedField] ~= selected then return end
            H.FocusKeyboardTarget(owner, selected, false, opts)
        end)
    end
end
function H.ArrowKeyDown(self, keyName, opts)
    opts = opts or {}
    local owner = (opts.owner and opts.owner(self)) or (self and self._preview) or self or (opts.active and opts.active())
    local dx, dy = H.KeyDelta(keyName)
    if not dx then
        SetKeyboardPropagate(self, true)
        return false
    end
    if H.IsTextInputFocused() then
        SetKeyboardPropagate(self, true)
        SetKeyboardPropagate(owner, true)
        return false
    end
    SetKeyboardPropagate(self, false)
    SetKeyboardPropagate(owner, false)
    if opts.nudge and opts.nudge(owner, dx, dy) then
        local selectedField = opts.selectedField or "_selectedHandle"
        local selected = (opts.selected and opts.selected(owner)) or (owner and selectedField and owner[selectedField])
        H.FocusKeyboardTarget(owner, selected, true, opts)
        return true
    end
    SetKeyboardPropagate(self, true)
    SetKeyboardPropagate(owner, true)
    return false
end
function H.RegisterEditModeNudgeTarget(owner, opts)
    local fn = _G.MSUF_EM2_SetPreviewNudgeTarget
    if type(fn) ~= "function" or not owner then return end
    opts = opts or {}
    local targetField = opts.targetField or "_msufPreviewNudgeTarget"
    local selectedField = opts.selectedField or "_selectedHandle"
    local function Selected() return opts.selected and opts.selected(owner) or (selectedField and owner[selectedField]) end
    owner[targetField] = owner[targetField] or {
        frame = owner,
        IsActive = function()
            if not (owner and owner.IsShown and owner:IsShown()) then return false end
            local selected = Selected()
            if opts.canNudge and not opts.canNudge(selected, owner) then return false end
            return selected ~= nil and not H.IsTextInputFocused()
        end,
        Nudge = function(_, dx, dy)
            local ok = opts.nudgeDelta and opts.nudgeDelta(owner, dx, dy)
            if ok then H.FocusKeyboardTarget(owner, Selected(), true, opts) end
            return ok
        end,
    }
    fn(owner[targetField])
end
local LAYER_BUTTON_FALLBACK_COLOR = { 1, 1, 1 }
local function LayerButtonAvailable(owner, key)
    return not (owner and owner.layerAvailable and owner.layerAvailable[key] == false)
end
local function LayerButtonOn(owner, key)
    return LayerButtonAvailable(owner, key) and not (owner and owner.layerVisibility and owner.layerVisibility[key] == false)
end
local function LayerButtonAvailableFor(owner, key, opts)
    if opts and opts.IsAvailable then return opts.IsAvailable(owner, key) end
    return LayerButtonAvailable(owner, key)
end
local function LayerButtonOnFor(owner, key, opts)
    if opts and opts.IsOn then return opts.IsOn(owner, key) end
    return LayerButtonOn(owner, key)
end
function H.RefreshLayerButton(btn, owner, opts)
    if not btn then return end
    opts = opts or {}
    local available = LayerButtonAvailableFor(owner, btn.key, opts)
    local on = LayerButtonOnFor(owner, btn.key, opts)
    local c = btn.color or LAYER_BUTTON_FALLBACK_COLOR
    if btn.off then
        btn.off:SetText(opts.offText or "OFF")
        btn.off:SetShown((not available) or not on)
    end
    if not available then
        btn.bg:SetColorTexture(0.020, 0.020, 0.028, 0.48)
        btn.bar:SetColorTexture(0.18, 0.18, 0.22, 0.35)
        btn.fs:SetTextColor(0.30, 0.30, 0.36, 0.55)
        btn.off:SetTextColor(0.36, 0.36, 0.42, 0.65)
    elseif on then
        btn.bg:SetColorTexture(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 0.58)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.88)
        btn.fs:SetTextColor(0.76, 0.80, 0.90, 0.95)
        btn.off:SetTextColor(0.36, 0.36, 0.42, 0.65)
    else
        btn.bg:SetColorTexture(0.035, 0.035, 0.045, 0.35)
        btn.bar:SetColorTexture(0.18, 0.18, 0.22, 0.32)
        btn.fs:SetTextColor(0.30, 0.30, 0.36, 0.55)
        btn.off:SetTextColor(0.40, 0.42, 0.50, 0.78)
    end
end
function H.CreateLayerButton(parent, owner, def, index, sideW, opts)
    if not (parent and def) then return nil end
    opts = opts or {}
    local tr = opts.Tr or F.Identity
    local btn = CreateFrame("Button", nil, parent)
    local h = opts.height or 18
    btn:SetSize((sideW or 80) - 10, h)
    btn:SetPoint("TOP", parent, "TOP", 0, -((opts.topOffset or 20) + ((index or 1) - 1) * (opts.rowHeight or h)))
    btn:EnableMouse(true)
    btn.key, btn.color, btn.tooltip = def.key, def.color, def.tooltip
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bar = btn:CreateTexture(nil, "ARTWORK")
    btn.bar:SetSize(2, 14)
    btn.bar:SetPoint("LEFT", btn, "LEFT", 2, 0)
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("LEFT", btn.bar, "RIGHT", 5, 0)
    btn.fs:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    btn.fs:SetJustifyH("LEFT")
    btn.fs:SetText(tr(def.label))
    btn.off = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.off:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn.off:SetText(opts.offText or "OFF")
    btn.off:SetJustifyH("RIGHT")
    function btn:Refresh() H.RefreshLayerButton(self, owner, opts) end
    btn.refresh = btn.Refresh
    btn:SetScript("OnClick", function(self)
        if opts.OnClick then
            opts.OnClick(self, owner)
            return
        end
        if not LayerButtonAvailable(owner, self.key) then return end
        owner.layerVisibility[self.key] = owner.layerVisibility[self.key] == false
        self:Refresh()
    end)
    btn:SetScript("OnEnter", function(self)
        local available = LayerButtonAvailableFor(owner, self.key, opts)
        local on = LayerButtonOnFor(owner, self.key, opts)
        local c = self.color or LAYER_BUTTON_FALLBACK_COLOR
        self.bg:SetColorTexture((available and on) and c[1] * 0.18 or 0.08, (available and on) and c[2] * 0.18 or 0.08, (available and on) and c[3] * 0.18 or 0.10, (available and on) and 0.78 or 0.55)
        self.fs:SetTextColor(0.90, 0.92, 1, 1)
        if opts.OnEnter then
            opts.OnEnter(self, owner, available, on, tr)
        elseif GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr(self.fs:GetText() or self.key), 1, 1, 1)
            if self.tooltip then GameTooltip:AddLine(tr(self.tooltip), 0.82, 0.82, 0.82, true) end
            if not available and opts.disabledLine then GameTooltip:AddLine(tr(opts.disabledLine), 0.55, 0.68, 0.86, true) end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self:Refresh()
        if opts.OnLeave then opts.OnLeave(self, owner) end
    end)
    btn:Refresh()
    return btn
end
local TEXT_FOCUS_SIDES = { "top", "bottom", "left", "right" }
local EDGE_ANCHORS = {
    top = { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    left = { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
    right = { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}
function H.NormalizeTextFocusKind(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end
function H.NormalizeTextFocusSlot(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end
function H.TextFocusColor(kind, colors)
    colors = colors or {}
    if kind == "hp" then return colors.hp or { 0.28, 0.86, 0.45 } end
    if kind == "power" then return colors.power or { 0.95, 0.72, 0.18 } end
    return colors.name or { 0.30, 0.66, 1.00 }
end
function H.EnsureTextFocusFrame(box, parent)
    if not (box and parent) then return nil end
    local f = box._msufMenuTextFocusFrame
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f:EnableMouse(false)
        f.fill = f:CreateTexture(nil, "BACKGROUND")
        f.fill:SetAllPoints()
        f.lines = {}
        for i = 1, #TEXT_FOCUS_SIDES do
            local side = TEXT_FOCUS_SIDES[i]
            local line = f:CreateTexture(nil, "OVERLAY")
            line:SetPoint(EDGE_ANCHORS[side][1])
            line:SetPoint(EDGE_ANCHORS[side][2])
            f.lines[side] = line
        end
        box._msufMenuTextFocusFrame = f
    elseif f.SetParent then
        f:SetParent(parent)
    end
    if f.SetFrameLevel and parent.GetFrameLevel then f:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
    return f
end
function H.PaintTextFocusFrame(frame, color, active)
    if not (frame and color) then return end
    local lineAlpha = active and 0.92 or 0.74
    local fillAlpha = active and 0.10 or 0.065
    local thickness = active and 2 or 1
    if frame.fill then frame.fill:SetColorTexture(color[1], color[2], color[3], fillAlpha) end
    if frame.lines then
        frame.lines.top:SetHeight(thickness)
        frame.lines.bottom:SetHeight(thickness)
        frame.lines.left:SetWidth(thickness)
        frame.lines.right:SetWidth(thickness)
        for _, line in pairs(frame.lines) do
            if line then line:SetColorTexture(color[1], color[2], color[3], lineAlpha) end
        end
    end
end
function H.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    opts = opts or {}
    pad = tonumber(pad) or 3
    local min, max = math.min, math.max
    local left, right, top, bottom
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() and region.GetLeft then
            local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
            if l and r and t and b then
                if opts.fitText then
                    local regionW = r - l
                    if region.GetStringWidth and regionW > 0 then
                        local textW = tonumber(region:GetStringWidth()) or 0
                        if textW > 0 and textW < regionW then
                            local justify = (region.GetJustifyH and region:GetJustifyH()) or region._msufPreviewJustifyH or "LEFT"
                            if justify == "RIGHT" then
                                l = r - textW
                            elseif justify == "CENTER" then
                                local cx = (l + r) * 0.5
                                l, r = cx - (textW * 0.5), cx + (textW * 0.5)
                            else
                                r = l + textW
                            end
                        end
                    end
                    local regionH = t - b
                    if region.GetStringHeight and regionH > 0 then
                        local textH = tonumber(region:GetStringHeight()) or 0
                        if textH > 0 and textH < regionH then
                            local cy = (t + b) * 0.5
                            t, b = cy + (textH * 0.5), cy - (textH * 0.5)
                        end
                    end
                end
                left = left and min(left, l) or l
                right = right and max(right, r) or r
                top = top and max(top, t) or t
                bottom = bottom and min(bottom, b) or b
            end
        end
    end
    local pLeft, pBottom = parent:GetLeft(), parent:GetBottom()
    if not (left and right and top and bottom and pLeft and pBottom) then return false end
    handle:ClearAllPoints()
    handle:SetSize(max(18, right - left + pad * 2), max(18, top - bottom + pad * 2))
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left - pLeft - pad, bottom - pBottom - pad)
    handle:Show()
    return true
end
function H.ApplyTextFocus(box, parent, mock, opts)
    opts = opts or {}
    local focus = box and box._msufMenuTextFocus
    local frame = box and box._msufMenuTextFocusFrame
    if not (focus and parent and mock) then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    local regions = opts.Regions and opts.Regions(mock, focus.kind, focus.slot)
    if not regions then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    frame = H.EnsureTextFocusFrame(box, parent)
    if not frame then return end
    local color = (opts.Color and opts.Color(focus.kind)) or H.TextFocusColor(focus.kind, opts.colors)
    H.PaintTextFocusFrame(frame, color, focus.active == true)
    if not (opts.Place and opts.Place(frame, parent, regions, focus.active and 5 or 4)) then frame:Hide() end
end
function H.SnapOff(region)
    if region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
end
function H.MaskOwner(mock, tex, anchor)
    local owner = tex and tex.GetParent and tex:GetParent() or nil
    if owner and owner.CreateMaskTexture then return owner end
    if anchor and anchor.CreateMaskTexture then return anchor end
    return mock
end
function H.EnsureRoundedMask(mock, key, anchor, tex, maskStoreKey, maskTexture, snapOff)
    if not (mock and anchor) then return nil end
    local owner = H.MaskOwner(mock, tex, anchor)
    if not (owner and owner.CreateMaskTexture) then return nil end
    maskStoreKey = maskStoreKey or "_msufPreviewRoundedMasks"
    mock[maskStoreKey] = mock[maskStoreKey] or {}
    local store = mock[maskStoreKey]
    local bucket = store[key]
    if type(bucket) ~= "table" or bucket.SetTexture then
        bucket = {}
        store[key] = bucket
    end
    local ownerKey = tex or owner
    local mask = bucket[ownerKey]
    if not mask then
        mask = owner:CreateMaskTexture(nil, "ARTWORK")
        local snap = snapOff or H.SnapOff
        snap(mask)
        bucket[ownerKey] = mask
    end
    if mask._msufPreviewRoundedAnchor ~= anchor or mask._msufPreviewRoundedTexture ~= maskTexture then
        mask._msufPreviewRoundedAnchor = anchor
        mask._msufPreviewRoundedTexture = maskTexture
        mask:ClearAllPoints()
        mask:SetTexture(maskTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(anchor)
    end
    return mask
end
function H.SetMask(mock, tex, mask, maskedStoreKey)
    if not (mock and tex and tex.AddMaskTexture) then return end
    maskedStoreKey = maskedStoreKey or "_msufPreviewRoundedMasked"
    mock[maskedStoreKey] = mock[maskedStoreKey] or {}
    local store = mock[maskedStoreKey]
    local old = store[tex]
    if old == mask then return end
    if old and tex.RemoveMaskTexture then tex:RemoveMaskTexture(old) end
    store[tex] = nil
    if mask then
        tex:AddMaskTexture(mask)
        store[tex] = mask
    end
end
function H.ClearMasks(mock, maskedStoreKey)
    local store = mock and mock[maskedStoreKey or "_msufPreviewRoundedMasked"]
    if store then
        for tex, mask in pairs(store) do
            if tex and tex.RemoveMaskTexture and mask then tex:RemoveMaskTexture(mask) end
        end
    end
    if mock then mock[maskedStoreKey or "_msufPreviewRoundedMasked"] = nil end
end
local EDGE_LINE_KEYS = { "top", "bottom", "left", "right" }
function H.SetEdgeLinesShown(frame, shown, opts)
    local lines = frame and frame[(opts and opts.linesKey) or "_lines"]
    if type(lines) ~= "table" then return end
    local keys = (opts and opts.keys) or EDGE_LINE_KEYS
    for i = 1, #keys do
        local line = lines[keys[i]]
        if line then
            if shown then line:Show() else line:Hide() end
        end
    end
end
function H.LayoutEdgeLines(frame, edge, opts)
    if not (frame and frame.CreateTexture) then return false end
    opts = opts or {}
    edge = H.ClampEdgeSize(edge, 1, opts.maxEdgeSize or 30)
    if edge <= 0 then H.SetEdgeLinesShown(frame, false, opts); return false end
    local linesKey = opts.linesKey or "_lines"
    local keys = opts.keys or EDGE_LINE_KEYS
    frame[linesKey] = frame[linesKey] or {}
    local lines = frame[linesKey]
    local texture = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local snap = opts.snapOff or H.SnapOff
    for i = 1, #keys do
        local key = keys[i]
        if not lines[key] then
            lines[key] = frame:CreateTexture(nil, opts.layer or "OVERLAY")
            lines[key]:SetTexture(texture)
            snap(lines[key])
        end
    end
    local r, g, b, a = 0, 0, 0, 1
    if type(opts.color) == "function" then r, g, b, a = opts.color(frame) end
    for i = 1, #keys do
        local key, line = keys[i], lines[keys[i]]
        local spec = EDGE_ANCHORS[key]
        line:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
        line:ClearAllPoints()
        line:SetPoint(spec[1], frame, spec[1], 0, 0)
        line:SetPoint(spec[2], frame, spec[2], 0, 0)
        line[spec[3]](line, edge)
    end
    H.SetEdgeLinesShown(frame, true, opts)
    return true
end
function H.ClampEdgeSize(value, fallback, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    n = math.floor(n + 0.5)
    if n < 0 then n = 0 end
    maxValue = tonumber(maxValue) or 8
    if n > maxValue then n = maxValue end
    return n
end
function H.EnsureRoundedVisuals(mock, opts)
    if not (mock and mock.CreateTexture) then return false end
    opts = opts or {}
    local bgKey = opts.bgKey or "roundedBg"
    local edgeKey = opts.edgeKey or "roundedEdge"
    local snap = opts.snapOff or H.SnapOff
    if not mock[bgKey] then
        mock[bgKey] = mock:CreateTexture(nil, opts.bgLayer or "BACKGROUND", nil, opts.bgSubLevel)
        mock[bgKey]:SetTexture(opts.whiteTexture or "Interface\\Buttons\\WHITE8X8")
        snap(mock[bgKey])
    end
    if not mock[edgeKey] then
        mock[edgeKey] = mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel)
        snap(mock[edgeKey])
    end
    if mock[edgeKey]._msufPreviewRoundedEdgeTexture ~= opts.edgeTexture then
        mock[edgeKey]._msufPreviewRoundedEdgeTexture = opts.edgeTexture
        mock[edgeKey]:SetTexture(opts.edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    return true
end
function H.ForEachRoundedEdge(mock, opts, fn)
    if not (mock and type(fn) == "function") then return end
    opts = opts or {}
    local edge = mock[opts.edgeKey or "roundedEdge"]
    if edge then fn(edge, 1) end
    local stack = mock[opts.stackKey or "_msufPreviewRoundedEdgeStack"]
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        if stack[i] then fn(stack[i], i) end
    end
end
function H.SetRoundedEdgeStackShown(mock, shown, opts)
    opts = opts or {}
    local count = shown and H.ClampEdgeSize(mock and mock[opts.countKey or "_msufPreviewRoundedEdgeCount"], 1, opts.maxEdgeSize or 8) or 0
    H.ForEachRoundedEdge(mock, opts, function(edge, i)
        if edge.SetShown then
            edge:SetShown(i <= count)
        elseif i <= count then
            edge:Show()
        else
            edge:Hide()
        end
    end)
end
function H.SetRoundedEdgeStackAlpha(mock, alpha, opts)
    local clamp = opts and opts.clamp01
    alpha = type(clamp) == "function" and clamp(alpha, 1) or math.max(0, math.min(1, tonumber(alpha) or 1))
    H.ForEachRoundedEdge(mock, opts, function(edge)
        if edge and edge.SetAlpha then edge:SetAlpha(alpha) end
    end)
end
function H.ApplyRoundedEdgeStack(mock, edgeSize, opts)
    if not mock then return false end
    opts = opts or {}
    local count = H.ClampEdgeSize(edgeSize, 0, opts.maxEdgeSize or 8)
    local stackKey = opts.stackKey or "_msufPreviewRoundedEdgeStack"
    local countKey = opts.countKey or "_msufPreviewRoundedEdgeCount"
    local edgeKey = opts.edgeKey or "roundedEdge"
    mock[countKey] = count
    if count <= 0 then
        H.SetRoundedEdgeStackShown(mock, false, opts)
        return false
    end
    mock[stackKey] = mock[stackKey] or {}
    mock[stackKey][1] = mock[edgeKey]
    local snap = opts.snapOff or H.SnapOff
    local edgeTexture = opts.edgeTexture
    local r, g, b, a
    if type(opts.baseEdgeColor) == "function" then
        r, g, b, a = opts.baseEdgeColor(mock)
    else
        r, g, b, a = H.BaseEdgeColor()
    end
    for i = 1, count do
        local edge = (i == 1) and mock[edgeKey] or mock[stackKey][i]
        if not edge then
            edge = mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel)
            snap(edge)
            mock[stackKey][i] = edge
        end
        if edge._msufPreviewRoundedEdgeTexture ~= edgeTexture then
            edge._msufPreviewRoundedEdgeTexture = edgeTexture
            edge:SetTexture(edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        if edge._msufPreviewRoundedAnchor ~= mock or edge._msufPreviewRoundedPad ~= i then
            edge._msufPreviewRoundedAnchor = mock
            edge._msufPreviewRoundedPad = i
            edge:ClearAllPoints()
            edge:SetPoint("TOPLEFT", mock, "TOPLEFT", -i, i)
            edge:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", i, -i)
        end
        if edge._msufPreviewRoundedR ~= r or edge._msufPreviewRoundedG ~= g
            or edge._msufPreviewRoundedB ~= b or edge._msufPreviewRoundedA ~= a then
            edge._msufPreviewRoundedR = r
            edge._msufPreviewRoundedG = g
            edge._msufPreviewRoundedB = b
            edge._msufPreviewRoundedA = a
            edge:SetVertexColor(r, g, b, a)
        end
        edge:Show()
    end
    H.SetRoundedEdgeStackShown(mock, true, opts)
    return true
end
function H.BaseEdgeColor()
    local fn = _G.MSUF_GetBarOutlineColor
    if type(fn) == "function" then
        local r, g, b = fn()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, 1 end
    end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        return tonumber(gen.barOutlineColorR) or 0,
               tonumber(gen.barOutlineColorG) or 0,
               tonumber(gen.barOutlineColorB) or 0,
               1
    end
    return 0, 0, 0, 1
end
