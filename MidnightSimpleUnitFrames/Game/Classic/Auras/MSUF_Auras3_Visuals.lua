local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Classic-only visual parity for the scan-based Auras3 backend.
--- Loaded exclusively by Classic-family manifests; Mainline keeps the native
--- AuraContainer visual implementation and pays no load/runtime cost here.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then return end

local V = A3.ClassicVisuals or {}
A3.ClassicVisuals = V

local type, tostring, tonumber, select, next = type, tostring, tonumber, select, next
local math_floor, math_max, math_min = math.floor, math.max, math.min
local CreateFrame = _G.CreateFrame
local STEALABLE_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"

local function Clamp(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = fallback end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Clamp01(value, fallback)
    return Clamp(value, fallback, 0, 1)
end

--- AuraData fields and unit answers can be secret (12.x engine clients). These
--- readers return a plain value of the asked kind, or nil for a secret or any
--- other kind, so the result can be compared and cached. The compiler and the
--- button code import them from here (Compile.lua loads after this file).
local IsSecret = _G.issecretvalue or function() return false end
function V.PlainNumber(value)
    if IsSecret(value) then return nil end
    return type(value) == "number" and value or nil
end
function V.PlainString(value)
    if IsSecret(value) then return nil end
    return type(value) == "string" and value or nil
end
function V.PlainBool(value)
    if IsSecret(value) then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

local Shape = A3.IconShape



-- The atlas probe, the shape stamp, the icon style painters and
-- A3.ApplyIconStylePreview are shared with Retail
-- (Auras3/MSUF_Auras3_IconShape.lua).
local AtlasKnown = Shape.AtlasKnown
local ApplyIconShape = Shape.ApplyIconShape

--- Classic buttons always take the flat swipe, even on an icon never shaped
--- (Shape.ApplyIconShape names the one difference to the Mainline stamp).
function A3.ApplyAuraIconShape(owner, shape, cooldown, ...)
    return ApplyIconShape(owner, shape, cooldown, false, ...)
end


local function Read(source, fallbackSource, key, fallback)
    local value = type(source) == "table" and source[key]
    if value == nil and type(fallbackSource) == "table" then value = fallbackSource[key] end
    if value == nil then value = fallback end
    return value
end

local function Color(value, dr, dg, db, da)
    value = type(value) == "table" and value or {}
    return Clamp01(value[1] or value.r, dr), Clamp01(value[2] or value.g, dg),
        Clamp01(value[3] or value.b, db), Clamp01(value[4] or value.a, da)
end

local ICON_STYLE_OFF = {
    borderEnabled = false,
    shadowEnabled = false,
    borderStyle = "SOLID",
    borderThickness = 1,
    shadowSize = 0,
}

function V.SharedIconStyle(shared, scope, appearanceKind)
    shared = type(shared) == "table" and shared or {}
    local normalized = tostring(scope or ""):lower()
    if normalized:match("^boss%d+$") then normalized = "boss" end
    local disabled = type(shared.styleScopeDisabled) == "table" and shared.styleScopeDisabled
    if normalized ~= "" and disabled and disabled[normalized] == true then return ICON_STYLE_OFF end
    local stylesByKind = type(shared.appearanceIconStyles) == "table" and shared.appearanceIconStyles or nil
    local style = stylesByKind and type(stylesByKind[appearanceKind]) == "table"
        and stylesByKind[appearanceKind] or shared
    local borderR, borderG, borderB, borderA = Color(style.styleBorderColor, 0, 0, 0, 1)
    local shadowR, shadowG, shadowB, shadowA = Color(style.styleShadowColor, 0, 0, 0, 0.8)
    local styles = MSUF.BorderStyles
    local key = styles and styles.Normalize(style.styleBorderStyle) or "SOLID"
    local texture = styles and styles.Resolve(key) or nil
    return {
        borderEnabled = style.styleBorderEnabled == true,
        borderStyle = key,
        borderTexture = texture,
        borderThickness = Clamp(style.styleBorderThickness, 1, 1, 8),
        borderR = borderR, borderG = borderG, borderB = borderB, borderA = borderA,
        borderEdge = texture and styles and styles.EdgeSize(key, Clamp(style.styleBorderThickness, 1, 1, 8)) or nil,
        borderPlacement = texture and styles and styles.Placement(key) or nil,
        shadowEnabled = style.styleShadowEnabled == true,
        shadowSize = Clamp(style.styleShadowSize, 4, 1, 16),
        shadowR = shadowR, shadowG = shadowG, shadowB = shadowB, shadowA = shadowA,
    }
end

local function Enrich(lane, layout, shared, prefix, portraitShape, scope)
    if not lane then return nil end
    local shapes = type(shared) == "table" and type(shared.appearanceIconShapes) == "table"
        and shared.appearanceIconShapes or nil
    local shapeValue = shapes and shapes[prefix]
        or Read(shared, nil, prefix .. "IconShape", Read(shared, nil, "iconShape", "RECTANGLE"))
    lane.iconShape = Shape.Resolve(shapeValue, portraitShape)
    lane.iconZoom = Clamp(Read(layout, nil, prefix .. "IconZoom", 100), 100, 100, 200)
    lane.cooldownSwipeReverse = Read(layout, nil, prefix .. "CooldownSwipeReverse", false) == true
    lane.showDurationBar = Read(layout, nil, prefix .. "ShowDurationBar", false) == true
    local display = tostring(Read(layout, nil, prefix .. "DurationBarDisplay", "BAR_ONLY")):upper()
    lane.durationBarDisplay = display == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    lane.durationBarHeight = Clamp(Read(layout, nil, prefix .. "DurationBarHeight", 2), 2, 1, 16)
    lane.durationBarPosition = tostring(Read(layout, nil, prefix .. "DurationBarPosition", "BOTTOM")):upper()
    lane.durationBarDirection = tostring(Read(layout, nil, prefix .. "DurationBarDirection", "REMAINING")):upper()
    lane.iconStyle = V.SharedIconStyle(shared, scope or lane.unit, prefix)
    lane.classicVisualStyle = true
    lane.buttonWidth = lane.buttonWidth or lane.size
    lane.buttonHeight = lane.buttonHeight or lane.size
    lane.stepX = lane.stepX or lane.step
    lane.stepY = lane.stepY or lane.step
    return lane
end

function V.EnrichUnitLane(lane, layout, sharedLayout, shared, kind, frameSpec)
    local merged = {}
    for key, value in pairs(type(sharedLayout) == "table" and sharedLayout or {}) do merged[key] = value end
    for key, value in pairs(type(layout) == "table" and layout or {}) do merged[key] = value end
    local prefix = kind == "debuff" and "debuff" or "buff"
    return Enrich(lane, merged, shared, prefix, frameSpec and frameSpec.portrait and frameSpec.portrait.shape, lane.unit)
end

function V.EnrichGroupLane(lane, source, kind, frameSpec, scope)
    local prefix = kind
    local db = _G.MSUF_DB
    local root = db and db.auras3
    local shared = root and root.shared or {}
    return Enrich(lane, source, shared, prefix, frameSpec and frameSpec.portrait and frameSpec.portrait.shape, scope)
end

function V.EnrichCustomLane(lane, entry, frameSpec)
    local placed = type(entry) == "table" and type(entry.placed) == "table" and entry.placed or {}
    local db = _G.MSUF_DB
    local root = db and db.auras3
    local shared = root and root.shared or {}
    local appearanceKind = lane.appearanceKind
        or (lane.harmful == true and "debuff" or "buff")
    local shapes = type(shared.appearanceIconShapes) == "table" and shared.appearanceIconShapes or nil
    lane.iconShape = Shape.Resolve(shapes and shapes[appearanceKind] or placed.iconShape,
        frameSpec and frameSpec.portrait and frameSpec.portrait.shape)
    lane.iconZoom = Clamp(placed.iconZoom, 100, 100, 200)
    lane.cooldownSwipeReverse = placed.cooldownSwipeReverse == true
    lane.showDurationBar = placed.showDurationBar == true
    lane.durationBarDisplay = tostring(placed.durationBarDisplay or "BAR_ONLY"):upper() == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    lane.durationBarHeight = Clamp(placed.durationBarHeight, 2, 1, 16)
    lane.durationBarPosition = tostring(placed.durationBarPosition or "BOTTOM"):upper()
    lane.durationBarDirection = tostring(placed.durationBarDirection or "REMAINING"):upper()
    lane.iconStyle = V.SharedIconStyle(shared, lane.unit, appearanceKind)
    lane.classicVisualStyle = true
    return lane
end

--- Shaped dispel-border geometry only: ring texture, texcoords and anchors.
--- It never colours or shows the texture. The live per-aura border caches the
--- colour it last wrote, so a colour painted behind that cache would survive
--- every later repaint of the same dispel type.
function A3.ApplyAuraDispelShape(border, icon, size, shape)
    shape = Shape.Normalize(shape)
    if shape == Shape.RECTANGLE then return false end
    local path = A3.AuraShapeBorderPath(shape)
    if not (border and icon and path) then return false end
    local pad = math_max(1, math_floor(((tonumber(size) or 24) / 24) + 0.5))
    border:SetTexture(path)
    if border.SetTexCoord then border:SetTexCoord(0, 1, 0, 1) end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    return true
end

--- Menu and Edit Mode previews: the shaped geometry plus the sample Magic colour.
function A3.ApplyAuraDispelPreview(border, icon, size, mode, shape)
    if mode == nil or mode == "OFF" then return false end
    if not A3.ApplyAuraDispelShape(border, icon, size, shape) then return false end
    border:SetVertexColor(0.20, 0.60, 1.00, 1)
    border:Show()
    return true
end

function V.ApplyButtonLayout(lane, button)
    local cfg = lane and lane.config
    if not (cfg and button) then return end
    local zoom = Clamp(cfg.iconZoom, 100, 100, 200)
    local inset = (1 - (100 / zoom)) * 0.5
    if button.Icon and button.Icon.SetTexCoord then button.Icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset) end
    local shape = cfg.iconShape or Shape.RECTANGLE
    ApplyIconShape(button, shape, button.Cooldown, false, button.Icon)
    A3.ApplyIconStylePreview(button, cfg.iconStyle, math_min(cfg.buttonWidth or cfg.size, cfg.buttonHeight or cfg.size), shape)
    if button.Cooldown and button.Cooldown.SetReverse then button.Cooldown:SetReverse(cfg.cooldownSwipeReverse == true) end
    local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if button.Icon and button.Icon.SetShown then button.Icon:SetShown(not barOnly)
    elseif button.Icon then if barOnly then button.Icon:Hide() else button.Icon:Show() end end
    -- UpdateCooldown owns whether this particular aura has a live timer. Do
    -- not resurrect the Cooldown merely because the lane allows cooldowns:
    -- permanent auras intentionally leave _msufA3CooldownShown unset.
    local showCooldown = not barOnly and cfg.showCooldown == true
        and button._msufA3CooldownShown == true
    if button.Cooldown and button.Cooldown.SetShown then button.Cooldown:SetShown(showCooldown)
    elseif button.Cooldown then if showCooldown then button.Cooldown:Show() else button.Cooldown:Hide() end end
    if button.Count and button.Count.SetShown then button.Count:SetShown(not barOnly and cfg.showStacks ~= false)
    elseif button.Count then if barOnly or cfg.showStacks == false then button.Count:Hide() else button.Count:Show() end end
    -- Layout generation stamp: the two inputs this pass was computed from.
    -- Written last, so a pass that raised is repeated by the next update.
    -- The indicator pass redraws after it, as this pass re-shows the icon.
    button._msufA3IndicatorConfig = nil
    button._msufA3NumberText = nil
    button._msufA3LayoutConfig = cfg
    button._msufA3LayoutCooldownShown = button._msufA3CooldownShown
end

-- Classic never binds aura LuaDurationObjects: C_UnitAuras.GetAuraDuration has
-- no engine-validated consumer on any Classic branch, and on Mists/TBC the
-- bound objects produced hour-scale timers. The bar animates from plain
-- duration/expiration numbers instead, the way Blizzard's own Classic timer
-- bars do.
local function DurationBarPaint(bar, now)
    local duration = bar._msufA3ClassicBarDuration
    local expiration = bar._msufA3ClassicBarExpiration
    if not (duration and expiration) then return end
    local remaining = expiration - now
    if remaining < 0 then remaining = 0 end
    bar:SetValue(bar._msufA3ClassicBarElapsed == true and (duration - remaining) or remaining)
end

--- One shared driver animates every shown duration bar (20 Hz) and re-checks
--- the cooldown-text colour buckets (4 Hz) that time alone moves, so a raid of
--- timed auras costs one OnUpdate instead of one per bar. It runs only while
--- something on screen is tracked: a bar while it is visible, a bucket while
--- its countdown is visible and its aura can still cross a threshold. Their
--- OnShow/OnHide follow a hidden parent; a show catches each up once.
local BAR_TICK, BUCKET_TICK = 0.05, 0.25
local tickBars, tickBuckets = {}, {}
local tickDriver
local barElapsed, bucketElapsed = 0, 0

local function TickDriverOnUpdate(_, elapsed)
    barElapsed = barElapsed + elapsed
    bucketElapsed = bucketElapsed + elapsed
    local now
    if barElapsed >= BAR_TICK then
        barElapsed = 0
        now = _G.GetTime()
        for bar in next, tickBars do DurationBarPaint(bar, now) end
    end
    if bucketElapsed >= BUCKET_TICK then
        bucketElapsed = 0
        local repaint = V.RepaintCooldownBucket
        if repaint then
            now = now or _G.GetTime()
            for cooldown in next, tickBuckets do repaint(cooldown, now) end
        end
    end
end

local function TickDriverSync()
    if next(tickBars) == nil and next(tickBuckets) == nil then
        if tickDriver and tickDriver._msufA3Running == true then
            tickDriver:Hide()
            tickDriver._msufA3Running = nil
        end
        return
    end
    if not tickDriver then
        tickDriver = CreateFrame("Frame")
        tickDriver:SetScript("OnUpdate", TickDriverOnUpdate)
    end
    if tickDriver._msufA3Running ~= true then
        tickDriver._msufA3Running = true
        tickDriver:Show()
    end
end

function V.TrackDurationBar(bar, track)
    track = track == true or nil
    if tickBars[bar] == track then return end
    tickBars[bar] = track
    TickDriverSync()
end

--- A countdown that becomes visible is re-checked once, then tracked while its
--- aura can still cross a threshold (the re-check may untrack it).
local function CooldownBucketOnShow(cooldown)
    if cooldown._msufA3BucketWanted ~= true then return end
    local repaint = V.RepaintCooldownBucket
    if repaint then repaint(cooldown, _G.GetTime()) end
    if cooldown._msufA3BucketWanted == true and tickBuckets[cooldown] ~= true then
        tickBuckets[cooldown] = true
        TickDriverSync()
    end
end

local function CooldownBucketOnHide(cooldown)
    if tickBuckets[cooldown] == true then
        tickBuckets[cooldown] = nil
        TickDriverSync()
    end
end

--- track: the countdown's aura can still cross a bucket threshold. The driver
--- re-checks it only while it is visible.
function V.TrackCooldownBucket(cooldown, track)
    track = track == true or nil
    cooldown._msufA3BucketWanted = track
    if track and cooldown._msufA3BucketHooked ~= true and cooldown.HookScript then
        cooldown._msufA3BucketHooked = true
        cooldown:HookScript("OnShow", CooldownBucketOnShow)
        cooldown:HookScript("OnHide", CooldownBucketOnHide)
    end
    local on = track and (not cooldown.IsVisible or cooldown:IsVisible() == true) or nil
    if tickBuckets[cooldown] == on then return end
    tickBuckets[cooldown] = on
    TickDriverSync()
end

--- What the shared driver currently animates (smokes read it).
function V.TimerTracked(object)
    return tickBars[object] == true or tickBuckets[object] == true
end

--- A bar under a hidden parent is not tracked (V.UpdateButtonVisual
--- skips it); it catches up here, once, when it becomes visible.
local function DurationBarOnShow(bar)
    if bar._msufA3ClassicBarExpiration then
        DurationBarPaint(bar, _G.GetTime())
        V.TrackDurationBar(bar, true)
    end
end

local function DurationBarOnHide(bar)
    V.TrackDurationBar(bar, false)
end

local function DurationBar(button, cfg)
    local bar = button._msufA3DurationBar
    if not bar then
        bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, button))
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar._msufA3ClassicBarMax = 1
        bar:SetScript("OnShow", DurationBarOnShow)
        bar:SetScript("OnHide", DurationBarOnHide)
        button._msufA3DurationBar = bar
    end
    -- Geometry and colour follow the compiled lane config alone (a new table
    -- for every config generation), so an unchanged refresh writes none.
    if bar._msufA3LayoutConfig == cfg then return bar end
    bar._msufA3LayoutConfig = cfg
    local height = Clamp(cfg.durationBarHeight, 2, 1, math_max(1, cfg.buttonHeight or cfg.size))
    local inset = math_max(1, math_floor(((cfg.buttonHeight or cfg.size or 24) / 32) + 0.5))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if cfg.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local color = general and general.aurasCooldownTextSafeColor
    local r, g, b = Color(color, 1, 1, 1, 0.95)
    bar:SetStatusBarColor(r, g, b, 0.95)
    return bar
end

local function FrameEffectHealthBar(frame)
    return frame and (frame.hpBar or frame.Health or frame.health)
end

local function FrameEffectHealthFill(frame)
    local bar = FrameEffectHealthBar(frame)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or bar
end

local function HideFrameEffect(button)
    local timer = button and button._msufA3ClassicFrameEffectTimer
    if timer and timer.Cancel then timer:Cancel() end
    if button then
        button._msufA3ClassicFrameEffectTimer = nil
        button._msufA3ClassicFrameEffectTimerAt = nil
        button._msufA3ClassicFrameEffectStamp = nil
    end
    local root = button and button._msufA3ClassicFrameEffectRoot
    -- Nothing drawn: a lane without an effect hides nothing on every update.
    if not (root and root._msufA3EffectDrawn == true) then return end
    root._msufA3EffectDrawn = nil
    local pulse = root._msufA3ClassicPulse
    if pulse and pulse.IsPlaying and pulse:IsPlaying() then pulse:Stop() end
    if root.SetAlpha then root:SetAlpha(1) end
    if root._tint then root._tint:Hide() end
    for i = 1, type(root._edges) == "table" and #root._edges or 0 do root._edges[i]:Hide() end
    if root._name then root._name:Hide() end
    root:Hide()
end

local function EnsureFrameEffectRoot(button, frame)
    local target = FrameEffectHealthBar(frame)
    if not (button and target) then return nil end
    local root = button._msufA3ClassicFrameEffectRoot
    if not root then
        -- Keep the effect surface as a unit-frame child so its configured
        -- absolute element layer can order below or above the Aura button.
        -- Classic AuraData is public, so button updates own visibility directly
        -- and no native secret-backed descendant gate is required here.
        root = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        if root.EnableMouse then root:EnableMouse(false) end
        root:Hide()
        button._msufA3ClassicFrameEffectRoot = root
    elseif root.GetParent and root:GetParent() ~= frame and root.SetParent then
        root:SetParent(frame)
    end
    root:ClearAllPoints()
    root:SetAllPoints(target)
    return root, target
end

local function ApplyFrameEffectEdges(root, target, effect, kind, r, g, b, a)
    local edges = root._edges
    if not edges then
        edges = {}
        for i = 1, 4 do
            edges[i] = PixelLayoutRegion(root:CreateTexture(nil, "OVERLAY"))
            edges[i]:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        root._edges = edges
    end
    local thickness = Clamp(effect.thickness, kind == "glow" and 3 or 2, 1, 32)
    if kind == "glow" or kind == "pulse" then thickness = thickness + 2 end
    edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness)
    edges[1]:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness); edges[1]:SetHeight(thickness)
    edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness)
    edges[2]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness); edges[2]:SetHeight(thickness)
    edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT", 0, 0); edges[3]:SetWidth(thickness)
    edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT", 0, 0); edges[4]:SetWidth(thickness)
    for i = 1, 4 do
        if edges[i].SetBlendMode then edges[i]:SetBlendMode(kind == "glow" and "ADD" or "BLEND") end
        edges[i]:SetVertexColor(r, g, b, kind == "glow" and math_min(1, a + 0.16) or a)
        edges[i]:Show()
    end
    if kind == "pulse" and root.CreateAnimationGroup then
        local pulse = root._msufA3ClassicPulse
        if not pulse then
            pulse = root:CreateAnimationGroup()
            local alpha = pulse:CreateAnimation("Alpha")
            alpha:SetFromAlpha(0.45); alpha:SetToAlpha(1); alpha:SetDuration(0.7)
            if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
            pulse:SetLooping("BOUNCE")
            root._msufA3ClassicPulse = pulse
        end
        if pulse.IsPlaying and not pulse:IsPlaying() then pulse:Play() end
    end
end

local function ApplyFrameEffect(lane, button, data)
    local cfg = lane and lane.config
    local effect = cfg and cfg.frameEffect
    local kind = type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
    if kind ~= "healthtint" and kind ~= "border" and kind ~= "glow"
        and kind ~= "pulse" and kind ~= "namecolor" then
        HideFrameEffect(button)
        return false
    end

    if tostring(effect.timing or "active"):lower() == "expiring" then
        local expiration = tonumber(data and data.expirationTime)
        local duration = tonumber(data and data.duration)
        local threshold = Clamp(effect.expireThreshold, 5, 1, 30)
        local now = _G.GetTime and _G.GetTime() or 0
        local remaining = expiration and expiration - now or 0
        if not (duration and duration > 0 and remaining > 0) then
            HideFrameEffect(button)
            return false
        end
        if remaining > threshold then
            -- One timer per aura application: a refresh that kept the same
            -- expiration and compiled config keeps the pending one. The
            -- config, not cfg.frameEffect: that is the stored profile table,
            -- which a menu edit (a new threshold) changes in place.
            if button._msufA3ClassicFrameEffectTimer
                and button._msufA3ClassicFrameEffectTimerAt == expiration
                and button._msufA3ClassicFrameEffectTimerConfig == cfg then
                return false
            end
            HideFrameEffect(button)
            local delay = remaining - threshold
            local timerAPI = _G.C_Timer
            if timerAPI and timerAPI.NewTimer then
                local auraInstanceID = button.auraInstanceID
                button._msufA3ClassicFrameEffectTimerAt = expiration
                button._msufA3ClassicFrameEffectTimerConfig = cfg
                button._msufA3ClassicFrameEffectTimer = timerAPI.NewTimer(delay, function()
                    button._msufA3ClassicFrameEffectTimer = nil
                    button._msufA3ClassicFrameEffectTimerAt = nil
                    if button.auraInstanceID == auraInstanceID and button._msufA3Shown == true then
                        ApplyFrameEffect(lane, button, data)
                    end
                end)
            end
            return false
        end
    end

    local frame = lane.ownerFrame
    -- Stamp: the effect drawn for this config on this frame stays as it is on
    -- an unchanged refresh, so a Pulse never restarts and nothing is re-laid.
    -- It is the compiled lane config (a new table per compile), never
    -- cfg.frameEffect: that is the stored profile table, which a menu edit
    -- changes in place, so a shown aura kept the old colour and kind.
    local drawn = button._msufA3ClassicFrameEffectRoot
    if drawn and button._msufA3ClassicFrameEffectStamp == cfg
        and button._msufA3ClassicFrameEffectFrame == frame then
        if kind == "namecolor" and drawn._name and frame then
            local source = frame.Name or frame.name or frame.NameText or frame.nameText or frame._nameFS
            local text = source and source.GetText and source:GetText()
            if text ~= drawn._name._msufA3Text then
                drawn._name:SetText(text)
                drawn._name._msufA3Text = text
            end
        end
        return true
    end
    local root, target = EnsureFrameEffectRoot(button, frame)
    if not root then HideFrameEffect(button); return false end
    HideFrameEffect(button)
    root, target = EnsureFrameEffectRoot(button, frame)
    local color = type(effect.color) == "table" and effect.color or {}
    local r, g, b, a = Color(color, 1, 1, 1, 1)
    if root.SetFrameLevel and frame and frame.GetFrameLevel then
        local priority = Clamp(effect.priority, 5, 1, 10)
        root:SetFrameLevel((frame:GetFrameLevel() or 0) + 12 - priority + Clamp(effect.layer, 0, 0, 30))
    end
    if kind == "healthtint" then
        local fill = FrameEffectHealthFill(frame)
        if not fill then return false end
        local tint = root._tint or PixelLayoutRegion(root:CreateTexture(nil, "OVERLAY"))
        root._tint = tint
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        tint:ClearAllPoints(); tint:SetAllPoints(fill)
        tint:SetVertexColor(r, g, b, Clamp(effect.tintAlpha or effect.alpha or a, 0.20, 0, 1))
        tint:Show()
    elseif kind == "namecolor" then
        local source = frame and (frame.Name or frame.name or frame.NameText or frame.nameText or frame._nameFS)
        if not source then return false end
        local overlay = root._name or PixelLayoutRegion(root:CreateFontString(nil, "OVERLAY"))
        root._name = overlay
        if source.GetFont and overlay.SetFont then
            local path, size, flags = source:GetFont()
            if path and size then overlay:SetFont(path, size, flags or "") end
        end
        if source.GetText then
            overlay._msufA3Text = source:GetText()
            overlay:SetText(overlay._msufA3Text)
        end
        overlay:ClearAllPoints(); overlay:SetAllPoints(source)
        overlay:SetTextColor(r, g, b, a); overlay:Show()
    else
        ApplyFrameEffectEdges(root, target, effect, kind, r, g, b, a)
    end
    root:Show()
    root._msufA3EffectDrawn = true
    button._msufA3ClassicFrameEffectStamp = cfg
    button._msufA3ClassicFrameEffectFrame = frame
    return true
end

-- Read-only stand-in for a lane without an indicator colour: this runs on
-- every button update, and Color only reads the table before its defaults.
local NO_INDICATOR_COLOR = {}

local function ApplyIndicatorVisual(button, cfg)
    -- Unit/group debuff lanes store their compiled dispel-frame visual in
    -- cfg.visual, while custom spell-indicator lanes store a normalized string
    -- in the same field.  Only the string form is an icon-mode instruction;
    -- treating the dispel table as a mode hides every normal debuff icon.
    local visual = type(cfg.visual) == "string" and cfg.visual or "icon"
    if visual ~= "icon" and visual ~= "square" and visual ~= "bar"
        and visual ~= "number" and visual ~= "none" then
        visual = "icon"
    end
    if visual ~= "icon" and button.Cooldown then button.Cooldown:Hide() end
    if visual == "none" and button.Count then button.Count:Hide() end
    -- Swatch, icon and glow follow the compiled lane config alone. The layout
    -- pass clears this stamp, as it re-shows the icon this pass may hide.
    if button._msufA3IndicatorConfig == cfg then return visual end
    local color = type(cfg.color) == "table" and cfg.color or NO_INDICATOR_COLOR
    local r, g, b, a = Color(color, 0.69, 0.50, 0.88, 1)
    local swatch = button._msufA3ClassicIndicatorSwatch
    if visual == "square" or visual == "bar" then
        if not swatch then
            swatch = PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY"))
            swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
            button._msufA3ClassicIndicatorSwatch = swatch
        end
        swatch:ClearAllPoints(); swatch:SetAllPoints(button)
        swatch:SetVertexColor(r, g, b, a); swatch:Show()
    elseif swatch then
        swatch:Hide()
    end
    local showIcon = visual == "icon"
    if button.Icon then button.Icon:SetShown(showIcon) end

    local glow = button._msufA3ClassicIconGlow
    if showIcon and cfg.iconEffect == "glow" then
        if not glow then
            glow = PixelLayoutRegion(button:CreateTexture(nil, "BACKGROUND"))
            glow:SetTexture("Interface\\Buttons\\WHITE8X8")
            button._msufA3ClassicIconGlow = glow
        end
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        glow:SetBlendMode("ADD"); glow:SetVertexColor(r, g, b, math_min(a, 0.55)); glow:Show()
    elseif glow then
        glow:Hide()
    end
    button._msufA3IndicatorConfig = cfg
    return visual
end

local function EnsureStealableTexture(button, key, subLevel)
    local texture = button[key]
    if texture then return texture end
    texture = PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY", nil, subLevel))
    texture:SetTexture(STEALABLE_TEXTURE)
    if texture.SetBlendMode then texture:SetBlendMode("ADD") end
    texture:Hide()
    button[key] = texture
    return texture
end

local function UpdateStealableMarker(button, cfg, data)
    local active = false
    if cfg.showStealableMarker == true and data then
        -- A secret stealable flag reads as unknown: no marker.
        local stealable = data.isStealable
        if IsSecret(stealable) then stealable = nil end
        active = stealable == true
    end
    -- Drawn once per config and stealable state.
    if button._msufA3StealableConfig == cfg and button._msufA3StealableActive == active then return end
    button._msufA3StealableConfig, button._msufA3StealableActive = cfg, active
    local border = button._msufA3ClassicStealableBorder
    local icon = button._msufA3ClassicStealableIcon
    if active ~= true then
        if border then border:Hide() end
        if icon then icon:Hide() end
        return
    end

    -- Compile.lua defines the normalizer; buttons render only after it loaded.
    local style = A3.NormalizeClassicStealableStyle(cfg.stealableStyle)
    if style == "BORDER" or style == "BORDER_ICON" then
        border = border or EnsureStealableTexture(button, "_msufA3ClassicStealableBorder", 5)
        border:ClearAllPoints()
        border:SetAllPoints(button)
        border:Show()
    elseif border then
        border:Hide()
    end
    if style == "ICON" or style == "BORDER_ICON" then
        icon = icon or EnsureStealableTexture(button, "_msufA3ClassicStealableIcon", 6)
        local size = math_max(8, math_floor(((cfg.size or 24) * 0.42) + 0.5))
        icon:ClearAllPoints()
        icon:SetSize(size, size)
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        icon:Show()
    elseif icon then
        icon:Hide()
    end
end

function V.UpdateButtonVisual(lane, button, unit, data)
    local cfg = lane and lane.config
    if not (cfg and button) then return end
    -- The layout depends only on the compiled lane config (a new table for
    -- every config generation) and on whether UpdateCooldown currently shows
    -- this button's cooldown. Re-apply it when either moved, so a refreshed
    -- aura that changed neither writes no layout at all.
    if button._msufA3LayoutConfig ~= cfg
        or button._msufA3LayoutCooldownShown ~= button._msufA3CooldownShown then
        V.ApplyButtonLayout(lane, button)
    end
    local visual = ApplyIndicatorVisual(button, cfg)
    if visual == "number" and button.Count then
        local applications = data and data.applications
        if IsSecret(applications) then
            -- A secret count goes to the C sink as it is and is never cached.
            button.Count:SetText(applications)
            button._msufA3NumberText = nil
        else
            applications = tonumber(applications) or 1
            if button._msufA3NumberText ~= applications then
                button.Count:SetText(applications)
                button._msufA3NumberText = applications
            end
        end
        button.Count:Show()
    end
    UpdateStealableMarker(button, cfg, data)
    ApplyFrameEffect(lane, button, data)
    if cfg.showDurationBar == true then
        local bar = DurationBar(button, cfg)
        -- A secret duration or expiration cannot drive the Lua bar: such an
        -- aura shows no bar, like a permanent one.
        local rawDuration, expiration = data and data.duration, data and data.expirationTime
        if IsSecret(rawDuration) or IsSecret(expiration) then rawDuration, expiration = nil, nil end
        rawDuration, expiration = tonumber(rawDuration), tonumber(expiration)
        local timed = rawDuration and expiration and rawDuration > 0 and expiration > 0
        if timed then
            local elapsedMode = cfg.durationBarDirection == "ELAPSED"
            -- A refresh of the same application leaves the bar to the driver.
            local same = bar._msufA3ClassicBarExpiration == expiration
                and bar._msufA3ClassicBarDuration == rawDuration
                and bar._msufA3ClassicBarElapsed == elapsedMode
            bar._msufA3ClassicBarDuration = rawDuration
            bar._msufA3ClassicBarExpiration = expiration
            bar._msufA3ClassicBarElapsed = elapsedMode
            if bar._msufA3ClassicBarMax ~= rawDuration then
                bar:SetMinMaxValues(0, rawDuration)
                bar._msufA3ClassicBarMax = rawDuration
            end
            if not (same and bar:IsShown()) then
                DurationBarPaint(bar, _G.GetTime())
                bar:Show()
            end
            -- Only a bar on screen is animated: under a hidden frame or lane
            -- its OnShow tracks it when it appears.
            V.TrackDurationBar(bar, bar:IsVisible())
        else
            -- Reusing a status bar after a timed aura must not retain its
            -- previous timer state for the next permanent aura.
            bar._msufA3ClassicBarDuration = nil
            bar._msufA3ClassicBarExpiration = nil
            if bar._msufA3ClassicBarMax ~= 1 then
                bar:SetMinMaxValues(0, 1)
                bar._msufA3ClassicBarMax = 1
            end
            bar:SetValue(0)
            bar:Hide()
            V.TrackDurationBar(bar, false)
        end
    elseif button._msufA3DurationBar then
        button._msufA3DurationBar:Hide()
        V.TrackDurationBar(button._msufA3DurationBar, false)
    end
end

function V.HideButtonVisual(button)
    if not button then return end
    if button._msufA3DurationBar then
        button._msufA3DurationBar:Hide()
        V.TrackDurationBar(button._msufA3DurationBar, false)
    end
    if button.Cooldown then V.TrackCooldownBucket(button.Cooldown, false) end
    if button._msufA3ClassicIndicatorSwatch then button._msufA3ClassicIndicatorSwatch:Hide() end
    if button._msufA3ClassicIconGlow then button._msufA3ClassicIconGlow:Hide() end
    if button._msufA3ClassicStealableBorder then button._msufA3ClassicStealableBorder:Hide() end
    if button._msufA3ClassicStealableIcon then button._msufA3ClassicStealableIcon:Hide() end
    button._msufA3IndicatorConfig = nil
    button._msufA3StealableConfig = nil
    HideFrameEffect(button)
end

V.DispelTypes = V.DispelTypes or { "Magic", "Curse", "Disease", "Poison", "Bleed" }

-- Shared Retail preview renderers ask the active Auras3 backend for a stable
-- sample dispel type before they know whether the Classic renderer will use
-- the value. Keep that backend contract available on every Classic client so
-- OFF/rectangle previews cannot fail while evaluating the call arguments.
function A3.PreviewDispelTypeForIndex(index)
    local types = V.DispelTypes
    index = math_max(1, math_floor(tonumber(index) or 1))
    return types[((index - 1) % #types) + 1]
end

V.DispelAtlases = V.DispelAtlases or {
    BLIZZARD = {
        Magic = "RaidFrame-Icon-DebuffMagic", Curse = "RaidFrame-Icon-DebuffCurse",
        Disease = "RaidFrame-Icon-DebuffDisease", Poison = "RaidFrame-Icon-DebuffPoison",
        Bleed = "RaidFrame-Icon-DebuffBleed",
    },
    BLIZZARD_RING = {
        Magic = "ui-debuff-border-magic-icon", Curse = "ui-debuff-border-curse-icon",
        Disease = "ui-debuff-border-disease-icon", Poison = "ui-debuff-border-poison-icon",
        Bleed = "ui-debuff-border-bleed-icon",
    },
    BLIZZARD_BORDER = {
        Magic = "ui-debuff-border-magic-noicon", Curse = "ui-debuff-border-curse-noicon",
        Disease = "ui-debuff-border-disease-noicon", Poison = "ui-debuff-border-poison-noicon",
        Bleed = "ui-debuff-border-bleed-noicon",
    },
}
V.DispelFolders = V.DispelFolders or {
    MSUF_LETTERS = "Letters", MSUF_SHAPES = "Shapes",
    MSUF_GLYPHS = "Glyphs", MSUF_MINIMAL = "Minimal",
}

--- Every MSUF set ships with the addon and covers all five dispel types, so
--- it is always a valid destination when a Blizzard atlas is unavailable.
local DISPEL_ART_FALLBACK_FOLDER = "Letters"

local function SetDispelSymbolFile(texture, folder, dispelType, tinted)
    local root = Shape.MEDIA_ROOT .. "\\Media\\Icons\\DispelTypes\\"
    if tinted then root = root .. "Tintable\\" end
    texture:SetTexture(root .. folder .. "\\" .. tostring(dispelType):lower() .. ".tga")
    if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
    return true
end

--- `tinted` mirrors Retail: a dispel type whose colour the user overrode is
--- drawn from the Tintable variant so the caller can repaint it. A Blizzard
--- atlas is pre-coloured and cannot honour an override, so an overridden type
--- always resolves to MSUF art.
function V.SetDispelSymbolArt(texture, style, dispelType, tinted)
    if not texture then return false end
    style = tostring(style or "BLIZZARD"):upper()
    local folder = V.DispelFolders[style]
    if folder then
        return SetDispelSymbolFile(texture, folder, dispelType, tinted)
    end
    if not tinted then
        local atlas = V.DispelAtlases[style] or V.DispelAtlases.BLIZZARD
        atlas = atlas and atlas[dispelType]
        if atlas and texture.SetAtlas and AtlasKnown(atlas) then
            texture:SetAtlas(atlas, _G.TextureKitConstants and _G.TextureKitConstants.IgnoreAtlasSize)
            return true
        end
    end
    --- Clients older than 12.1 ship none of these debuff atlases. Blanking the
    --- texture left a correctly sized but completely invisible symbol row, so
    --- fall back to MSUF art instead of rendering nothing.
    return SetDispelSymbolFile(texture, DISPEL_ART_FALLBACK_FOLDER, dispelType, tinted)
end

function V.HideDispelSymbols(frame, preview)
    local hostKey = preview == true and "_msufA3ClassicDispelSymbolPreviewHost" or "_msufA3ClassicDispelSymbolHost"
    local activeKey = preview == true and "_msufA3ClassicDispelSymbolPreviewActive" or "_msufA3ClassicDispelSymbolsActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelSymbolPreviewSignature" or "_msufA3ClassicDispelSymbolSignature"
    local host = frame and frame[hostKey]
    local changed = frame and frame[activeKey] == true or false
    if host then host:Hide() end
    if frame then
        frame[activeKey] = nil
        frame[signatureKey] = nil
    end
    return changed
end

--- The preview host's drag as saved offsets (A3.HostAnchorOffset in
--- Auras3/MSUF_Auras3_Core.lua), rounded half away from zero.
function V.DispelPreviewAnchorOffset(host, parent, anchor)
    local x, y = A3.HostAnchorOffset(host, parent, tostring(anchor or "TOPRIGHT"):upper())
    if x == nil then return nil, nil end
    x = x >= 0 and math_floor(x + 0.5) or -math_floor((-x) + 0.5)
    y = y >= 0 and math_floor(y + 0.5) or -math_floor((-y) + 0.5)
    return x, y
end

function V.OnDispelPreviewDragStart(host)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    host:StartMoving()
end

function V.OnDispelPreviewDragStop(host)
    host:StopMovingOrSizing()
    local frame = host._msufA3ClassicDispelPreviewParent
    local visual = host._msufA3ClassicDispelPreviewVisual
    local handler = A3.DispelSymbolPreviewMoveHandler
    if not (frame and visual and visual.symbol) then return end
    local x, y = V.DispelPreviewAnchorOffset(host, frame, visual.symbol.anchor)
    if x == nil then return end
    if type(handler) == "function" then
        handler(_G.MSUF_DispelSymbolPreviewScope, x, y, frame)
    end
    -- Only the preview host is draggable, and Preview.lua renders it.
    A3.RefreshDispelSymbolPreview()
end

function V.UpdateDispelSymbols(frame, visual, present, preview)
    local hostKey = preview == true and "_msufA3ClassicDispelSymbolPreviewHost" or "_msufA3ClassicDispelSymbolHost"
    local activeKey = preview == true and "_msufA3ClassicDispelSymbolPreviewActive" or "_msufA3ClassicDispelSymbolsActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelSymbolPreviewSignature" or "_msufA3ClassicDispelSymbolSignature"
    local cfg = visual and visual.symbol
    if not (frame and cfg and cfg.enabled == true and type(present) == "table") then
        return V.HideDispelSymbols(frame, preview)
    end
    -- Per-frame scratch list reused across updates; only its array part is
    -- ever filled, so clearing that part is a full reset.
    local selectedKey = preview == true and "_msufA3ClassicDispelSymbolPreviewSelected" or "_msufA3ClassicDispelSymbolSelected"
    local selected = frame[selectedKey]
    if selected then
        for i = #selected, 1, -1 do selected[i] = nil end
    else
        selected = {}
        frame[selectedKey] = selected
    end
    for i = 1, #V.DispelTypes do
        local dispelType = V.DispelTypes[i]
        if present[dispelType] == true then
            selected[#selected + 1] = dispelType
            if cfg.mode ~= "ALL" then break end
        end
    end
    if #selected == 0 then return V.HideDispelSymbols(frame, preview) end
    --- An explicit strata stays on the host until it is written again, so AUTO
    --- restores the frame's strata instead of keeping the last explicit one.
    --- The signature keys on the resolved strata: keyed on "AUTO", a later
    --- change of the frame's own strata never reached the host.
    local strata = cfg.strata
    if strata == nil or strata == "AUTO" then strata = A3.ReadParentFrameStrata(frame) end
    local signature = table.concat(selected, ",") .. ":" .. tostring(cfg.style) .. ":"
        .. tostring(cfg.size) .. ":" .. tostring(cfg.spacing) .. ":" .. tostring(cfg.growth)
        .. ":" .. tostring(cfg.anchor) .. ":" .. tostring(cfg.x) .. ":" .. tostring(cfg.y)
        .. ":" .. tostring(cfg.alpha) .. ":" .. tostring(cfg.layer) .. ":" .. tostring(strata)
        -- Stamped by the compile, never rebuilt here: a colour override has to
        -- invalidate the cached signature or the tiles never repaint.
        .. ":" .. tostring(cfg.tintKey or "")
    local host = frame[hostKey]
    if not host then
        host = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        if preview == true then
            host:SetMovable(true)
            host:EnableMouse(true)
            host:RegisterForDrag("LeftButton")
            host:SetScript("OnDragStart", V.OnDispelPreviewDragStart)
            host:SetScript("OnDragStop", V.OnDispelPreviewDragStop)
        elseif host.EnableMouse then
            host:EnableMouse(false)
        end
        host.tiles = {}
        frame[hostKey] = host
    end
    if preview == true then
        host._msufA3ClassicDispelPreviewParent = frame
        host._msufA3ClassicDispelPreviewVisual = visual
    end
    if frame[signatureKey] == signature and host:IsShown() then return false end
    local size = Clamp(cfg.size, 14, 4, 64)
    local spacing = Clamp(cfg.spacing, 2, 0, 32)
    local growth = tostring(cfg.growth or "RIGHT"):upper()
    local horizontal = growth == "RIGHT" or growth == "LEFT"
    local xSign = growth == "LEFT" and -1 or 1
    local ySign = growth == "DOWN" and -1 or 1
    host:ClearAllPoints(); host:SetPoint(cfg.anchor or "TOPRIGHT", frame, cfg.anchor or "TOPRIGHT", cfg.x or 0, cfg.y or 0)
    host:SetSize(horizontal and (#selected * size + math_max(0, #selected - 1) * spacing) or size,
        horizontal and size or (#selected * size + math_max(0, #selected - 1) * spacing))
    if host.SetAlpha then host:SetAlpha(Clamp01(cfg.alpha, 1)) end
    if host.SetFrameStrata and strata then host:SetFrameStrata(strata) end
    if host.SetFrameLevel and frame.GetFrameLevel then host:SetFrameLevel((frame:GetFrameLevel() or 0) + Clamp(cfg.layer, 8, 0, 30)) end
    for i = 1, #selected do
        local tile = host.tiles[i]
        if not tile then
            tile = PixelLayoutRegion(host:CreateTexture(nil, "OVERLAY"))
            host.tiles[i] = tile
        end
        tile:ClearAllPoints(); tile:SetSize(size, size)
        local offset = (i - 1) * (size + spacing)
        if horizontal then
            tile:SetPoint(xSign > 0 and "LEFT" or "RIGHT", host, xSign > 0 and "LEFT" or "RIGHT", offset * xSign, 0)
        else
            tile:SetPoint(ySign > 0 and "BOTTOM" or "TOP", host, ySign > 0 and "BOTTOM" or "TOP", 0, offset * ySign)
        end
        local dispelType = selected[i]
        local tint = cfg.tint and cfg.tint[dispelType] or nil
        if V.SetDispelSymbolArt(tile, cfg.style, dispelType, tint ~= nil) then
            if tile.SetVertexColor then
                if tint then
                    tile:SetVertexColor(tint[1], tint[2], tint[3])
                else
                    tile:SetVertexColor(1, 1, 1)
                end
            end
            tile:Show()
        else
            tile:Hide()
        end
    end
    for i = #selected + 1, #host.tiles do host.tiles[i]:Hide() end
    frame[activeKey] = true
    frame[signatureKey] = signature
    host:Show()
    return true
end

function V.UpdateDispelSymbolPreview(frame, visual, active)
    if active ~= true then return V.HideDispelSymbols(frame, true) end
    local present = {}
    for i = 1, #V.DispelTypes do present[V.DispelTypes[i]] = true end
    return V.UpdateDispelSymbols(frame, visual, present, true)
end

function V.HideDispelOverlay(frame, preview)
    local hostKey = preview == true and "_msufA3ClassicDispelOverlayPreviewHost" or "_msufA3ClassicDispelOverlayHost"
    local activeKey = preview == true and "_msufA3ClassicDispelOverlayPreviewActive" or "_msufA3ClassicDispelOverlayActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelOverlayPreviewSignature" or "_msufA3ClassicDispelOverlaySignature"
    local host = frame and frame[hostKey]
    local changed = frame and frame[activeKey] == true or false
    if host then host:Hide() end
    if frame then
        frame[activeKey] = nil
        frame[signatureKey] = nil
    end
    return changed
end

--- A menu preview's dispel overlay: this backend's strip layout in the
--- spec's dispel colour (the scan backend has no preview dispel type).
function A3.PaintDispelOverlayPreview(region, target, style, thickness, dispel)
    region:ClearAllPoints()
    MSUF.BorderStyles.LayoutEdgeStrip(region, target, style, thickness)
    region:SetColorTexture(tonumber(dispel and dispel.r) or 0.25,
        tonumber(dispel and dispel.g) or 0.75, tonumber(dispel and dispel.b) or 1, 1)
end

--- Scan-backend equivalent of Retail's native AddDispelTypeTexture overlay.
--- It is reached only when the compiled frame visual enables the feature; the
--- disabled path owns no frame, event or API work.
function V.UpdateDispelOverlay(frame, visual, active, r, g, b, a, preview)
    if not (frame and visual and visual.overlayEnabled == true and active == true) then
        return V.HideDispelOverlay(frame, preview)
    end
    local hostKey = preview == true and "_msufA3ClassicDispelOverlayPreviewHost" or "_msufA3ClassicDispelOverlayHost"
    local activeKey = preview == true and "_msufA3ClassicDispelOverlayPreviewActive" or "_msufA3ClassicDispelOverlayActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelOverlayPreviewSignature" or "_msufA3ClassicDispelOverlaySignature"
    local style = tostring(visual.overlayStyle or "FULL"):upper()
    local alpha = Clamp01(visual.overlayAlpha, 0.35) * Clamp01(a, 1)
    r, g, b = Clamp01(r, 0.25), Clamp01(g, 0.75), Clamp01(b, 1)
    local target = visual.overlayOnHealth == true and (frame.hpBar or frame.Health) or frame
    if not target then return V.HideDispelOverlay(frame, preview) end
    local signature = style .. ":" .. tostring(alpha) .. ":" .. tostring(r) .. ":"
        .. tostring(g) .. ":" .. tostring(b) .. ":" .. tostring(target)
    local host = frame[hostKey]
    if not host then
        host = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        host:SetAllPoints(frame)
        if host.EnableMouse then host:EnableMouse(false) end
        host.region = PixelLayoutRegion(host:CreateTexture(nil, "OVERLAY"))
        frame[hostKey] = host
    end
    if frame[signatureKey] == signature and host:IsShown() then return false end
    local region = host.region
    region:ClearAllPoints()
    MSUF.BorderStyles.LayoutEdgeStrip(region, target, style, 3)
    region:SetColorTexture(r, g, b, 1)
    region:SetAlpha(alpha)
    if host.SetFrameLevel and frame.GetFrameLevel then host:SetFrameLevel((frame:GetFrameLevel() or 0) + 8) end
    region:Show()
    frame[activeKey] = true
    frame[signatureKey] = signature
    host:Show()
    return true
end

function V.UpdateDispelOverlayPreview(frame, visual, active)
    return V.UpdateDispelOverlay(frame, visual, active,
        visual and visual.r, visual and visual.g, visual and visual.b, 1, true)
end
