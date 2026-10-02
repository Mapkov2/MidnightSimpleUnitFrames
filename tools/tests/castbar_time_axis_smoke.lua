-- castbar_time_axis_smoke.lua <repoRoot>
--
-- Castbar decorations that sit on the cast's time axis must follow the way the
-- bar actually moves. A cast (and a channel with unified direction) fills away
-- from its anchor; a channel in the default, non-unified direction drains
-- toward it. The fixtures below model that movement explicitly: every check
-- converts a drawn position back into the moment the moving fill edge reaches
-- it, instead of trusting an anchor side.
--
-- 1. "Highlight last channel tick" accents the tick the edge reaches last.
-- 2. The interrupt-ready time marker sits where the moving edge will be when
--    the interrupt recovers, the shade covers exactly the time after it, both
--    stay inside the bar (hidden when the interrupt recovers after the cast),
--    draw below the cast text, keep the bar's masks, pass restricted times
--    straight to native sinks, write only the value sinks per refresh, and
--    follow a cooldown reduction that leaves the ready state unchanged.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local WIDTH = 200

---------------------------------------------------------------------------
-- Minimal region model: textures remember their anchors, width and colour.
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region
local function NewRegion(kind, parent)
    return setmetatable({ kind = kind, parent = parent, points = {}, shown = false, alpha = 1 }, Region)
end
function Region:SetPoint(point, relative, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relative, relativePoint, x or 0, y or 0 }
end
function Region:ClearAllPoints() self.points = {} end
function Region:SetWidth(value) self.width = value end
function Region:SetHeight(value) self.height = value end
function Region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Region:SetAlpha(value) self.alpha = value end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(value) self.shown = value and true or false end
function Region:GetWidth() return self.fixedWidth or 0 end
function Region:CreateTexture() return NewRegion("Texture", self) end
function Region:HookScript(name, callback) self.hooks = self.hooks or {}; self.hooks[name] = callback end

---------------------------------------------------------------------------
-- Load the real castbar utilities (count direction) and channel tick module.
---------------------------------------------------------------------------
local function LoadTickModule(flavor)
    issecretvalue = function() return false end
    IsPlayerSpell = function() return false end
    C_Timer = { After = function() end }
    MSUF_DB = { general = {}, player = { castbar = {} } }
    local ns = {
        Client = { IsForever = false, IsVanilla = flavor == "Vanilla", IsRetail = flavor == "Mainline" },
        ExportPublic = function(name, value) _G[name] = value end,
    }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MSUF", ns)
    Check(type(_G.MSUF_GetCastbarCountsDown) == "function", "castbar utilities no longer export the count direction")
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarChannelTicks.lua"))("MSUF", ns)
    return _G.MSUF_PlayerChannelHasteMarkers_Update
end

local function ChannelFrame(spellID, reverse)
    local statusBar = NewRegion("StatusBar")
    statusBar.fixedWidth = WIDTH
    return {
        unit = "player",
        statusBar = statusBar,
        MSUF_isChanneled = true,
        _msufActiveSpellID = spellID,
        _msufStripeReverseFill = reverse == true,
    }
end

-- Offset of a marker from the fill anchor, read back from its anchors.
local function AnchorOffset(marker, reverse)
    local point = Check(marker.points[1], "tick marker has no anchor")
    if reverse then
        Check(point[3] == "TOPRIGHT", "reverse-filled tick marker is not measured from the right edge")
        return -point[4]
    end
    Check(point[3] == "TOPLEFT", "tick marker is not measured from the left edge")
    return point[4]
end

-- The moment (0..1 of the channel) the moving fill edge reaches an offset.
local function ReachedAt(offset, countsDown)
    local fraction = offset / WIDTH
    if countsDown then return 1 - fraction end
    return fraction
end

local function IsAccent(marker)
    return marker.width == 3 and marker.color and marker.color[2] < 1
end

local function CheckAccent(update, spellID, options, label)
    local general = MSUF_DB.general
    general.castbarShowChannelTicks = true
    general.castbarAccentLastTick = true
    general.castbarUnifiedDirection = options.unified == true
    local castbar = MSUF_DB.player.castbar
    castbar.channelTickUseCustom = options.custom ~= nil
    castbar.channelTickCount = options.custom and #options.custom or nil
    castbar.channelTickPosPct = options.custom
    local frame = ChannelFrame(spellID, options.reverse)
    local countsDown = options.unified ~= true
    -- A running bar carries the direction it was bound with; previews carry
    -- none and fall back to the cast-type rule. A setting toggled mid-channel
    -- does not rebind the running bar, so the recorded direction wins.
    if options.recorded == "match" then frame._msufCountsDown = countsDown
    elseif options.recorded == "stale" then
        frame._msufCountsDown = not countsDown
        countsDown = not countsDown
    end
    -- A partial load without the castbar utilities applies the same rule.
    local helper = _G.MSUF_GetCastbarCountsDown
    if options.noHelper then _G.MSUF_GetCastbarCountsDown = nil end
    update(frame, true)
    _G.MSUF_GetCastbarCountsDown = helper
    local markers = Check(frame._msufPlayerChannelHasteMarkers, label .. ": no tick markers were created")
    local shown, accented, latest, latestMarker = 0, 0, -1, nil
    for index = 1, #markers do
        local marker = markers[index]
        if marker.shown then
            shown = shown + 1
            if IsAccent(marker) then accented = accented + 1 end
            local at = ReachedAt(AnchorOffset(marker, options.reverse), countsDown)
            if at > latest then latest, latestMarker = at, marker end
        end
    end
    Check(shown == (options.expected or shown) and shown > 1, label .. ": unexpected tick count " .. shown)
    Check(accented == 1, label .. ": expected exactly one accented tick, found " .. accented)
    Check(IsAccent(latestMarker), label .. ": the accent is not on the tick the fill edge reaches last")
    general.castbarAccentLastTick = false
    update(frame, true)
    for index = 1, #markers do
        Check(not IsAccent(markers[index]), label .. ": accent survived switching the option off")
    end
end

do
    -- Classic Era data: Arcane Missiles rank 3 ticks five times (four markers).
    local update = LoadTickModule("Vanilla")
    CheckAccent(update, 5145, { expected = 4 }, "Era draining channel (preview, no recorded direction)")
    CheckAccent(update, 5145, { expected = 4, recorded = "match" }, "Era draining channel")
    CheckAccent(update, 5145, { expected = 4, recorded = "match", reverse = true }, "Era draining reverse-filled channel")
    CheckAccent(update, 5145, { expected = 4, recorded = "match", unified = true }, "Era unified channel")
    CheckAccent(update, 5145, { expected = 4, unified = true, reverse = true }, "Era unified reverse-filled preview")
    CheckAccent(update, 5145, { expected = 4, recorded = "stale" }, "Era channel after a mid-channel direction toggle")
    CheckAccent(update, 5145, { expected = 4, recorded = "stale", unified = true }, "Era unified toggle mid-channel")
    CheckAccent(update, 5145, { expected = 4, noHelper = true }, "Era draining channel without castbar utilities")
    CheckAccent(update, 5145, { expected = 4, noHelper = true, unified = true }, "Era unified channel without castbar utilities")
    -- Custom positions are stored in any order; the accent still follows time.
    CheckAccent(update, 5145, { custom = { 70, 20, 90, 40 } }, "custom draining channel")
    CheckAccent(update, 5145, { custom = { 70, 20, 90, 40 }, unified = true }, "custom unified channel")
    CheckAccent(update, 5145, { custom = { 70, 20, 90, 40 }, reverse = true }, "custom draining reverse-filled channel")
end
do
    -- Midnight data: Mind Flay ticks six times (five markers).
    local update = LoadTickModule("Mainline")
    CheckAccent(update, 15407, { expected = 5 }, "Midnight draining channel")
    CheckAccent(update, 15407, { expected = 5, unified = true }, "Midnight unified channel")
end

print("castbar_time_axis_smoke: tick accent OK")

---------------------------------------------------------------------------
-- 2. Interrupt-ready time projection
---------------------------------------------------------------------------
do
    -- Restricted numbers: any Lua arithmetic or comparison raises. Only the
    -- native sinks below unwrap them.
    local SecretMT = {}
    local function Refuse() error("restricted value used in Lua arithmetic or comparison", 2) end
    for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__lt", "__le", "__eq", "__concat", "__tostring" }) do
        SecretMT[event] = Refuse
    end
    local function Secret(value) return setmetatable({ __plain = value }, SecretMT) end
    local function Unwrap(value)
        if getmetatable(value) == SecretMT then return rawget(value, "__plain") end
        return value
    end
    local function IsSecret(value) return getmetatable(value) == SecretMT end

    local writes = 0
    local LAYOUT = { ClearAllPoints = true, SetPoint = true, SetColorTexture = true, SetShown = true,
        Show = true, Hide = true, SetAlpha = true, SetAlphaFromBoolean = true, AddMaskTexture = true,
        RemoveMaskTexture = true, SetReverseFill = true, SetWidth = true }
    local N = {}
    N.__index = function(self, key)
        local method = N[key]
        if method and LAYOUT[key] then
            return function(...) writes = writes + 1; return method(...) end
        end
        return method
    end
    local named = {}
    local function Node(kind, parent, layer, sublevel)
        return setmetatable({ kind = kind, parent = parent, points = {}, shown = kind ~= "Texture",
            alpha = 1, layer = layer, sublevel = sublevel, masks = {} }, N)
    end
    function N.SetPoint(self, point, relative, relativePoint, x, y)
        self.points[#self.points + 1] = { point, relative, relativePoint or point, x or 0, y or 0 }
    end
    function N.SetAllPoints(self, relative) self.allPoints = relative end
    function N.ClearAllPoints(self) self.points = {}; self.allPoints = nil end
    function N.SetWidth(self, value) self.width = value end
    function N.SetSize(self, w, h) self.width, self.height = w, h end
    function N.SetColorTexture(self, r, g, b, a) self.color = { r, g, b, a } end
    function N.SetVertexColor(self, r, g, b, a) self.color = { r, g, b, a } end
    function N.SetTexture(self, ...) self.texture = { ... } end
    function N.SetAlpha(self, value) self.alpha = value end
    function N.SetAlphaFromBoolean(self, value, whenTrue, whenFalse)
        Check(IsSecret(value) or type(value) == "boolean", "SetAlphaFromBoolean needs a boolean")
        self.alpha = Unwrap(value) and whenTrue or whenFalse
    end
    function N.Show(self) self.shown = true end
    function N.Hide(self) self.shown = false end
    function N.SetShown(self, value) self.shown = value and true or false end
    function N.IsShown(self) return self.shown end
    function N.SetFrameLevel(self, value) self.level = value end
    function N.GetFrameLevel(self) return self.level or 1 end
    function N.SetScript(self, name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
    function N.RegisterEvent(self, event) self.events = self.events or {}; self.events[event] = true end
    function N.UnregisterEvent(self, event) if self.events then self.events[event] = nil end end
    function N.UnregisterAllEvents(self) self.events = {} end
    function N.SetStatusBarTexture(self)
        self.fill = self.fill or Node("Texture", self, "ARTWORK", 0)
        self.fill.fillOf = self
    end
    function N.GetStatusBarTexture(self) return self.fill end
    function N.SetStatusBarColor(self, r, g, b, a) self.barColor = { r, g, b, a } end
    function N.SetMinMaxValues(self, minimum, maximum) self.minimum, self.maximum = minimum, maximum; self.valueWrites = (self.valueWrites or 0) + 1 end
    function N.SetValue(self, value) self.value = value; self.valueWrites = (self.valueWrites or 0) + 1 end
    function N.SetReverseFill(self, value) self.reverse = value == true end
    function N.CreateTexture(self, _, layer, _, sublevel) return Node("Texture", self, layer, sublevel) end
    function N.CreateMaskTexture(self, _, layer) return Node("MaskTexture", self, layer) end
    function N.CreateFontString(self, _, layer) return Node("FontString", self, layer) end
    function N.AddMaskTexture(self, mask)
        Check(mask.kind == "MaskTexture", "only mask textures mask")
        for _, existing in ipairs(self.masks) do Check(existing ~= mask, "mask attached twice") end
        self.masks[#self.masks + 1] = mask
    end
    function N.RemoveMaskTexture(self, mask)
        for index, existing in ipairs(self.masks) do
            if existing == mask then table.remove(self.masks, index); return end
        end
    end
    function N.GetNumMaskTextures(self) return #self.masks end
    function N.GetMaskTexture(self, index) return self.masks[index] end

    CreateFrame = function(kind, name, parent)
        local node = Node(kind, parent)
        if name then named[name] = node end
        return node
    end
    UIParent = Node("Frame")
    issecretvalue = IsSecret
    -- Every refresh below happens on a later rendered frame, as in game.
    local frameTime = 100
    GetTime = function() frameTime = frameTime + 0.016; return frameTime end
    C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
    C_SpellBook = { IsSpellKnownOrInSpellBook = function() return false end }
    UnitClass = function() return "Warrior", "WARRIOR" end
    MSUF_ShouldUseMSUFCastbar = function() return true end
    local kickEnd = 103
    local cooldownFactory = function()
        return { GetEndTime = function() return kickEnd end, GetRemainingDuration = function() return 5 end }
    end
    C_Spell = { GetSpellCooldownDuration = function() return cooldownFactory() end }
    MSUF_DB = { general = { kickReadyShowTarget = true, kickReadyStyle = "border",
        kickReadyTimeMarker = true, kickReadyTimeSegment = true } }
    local ns = { Client = { IsRetail = true }, ExportPublic = function(name, value) _G[name] = value end,
        Scheduler = { ScheduleAfter = function() return true end, CancelScheduled = function() return false end } }
    -- Castbars/MSUF_CastbarUtils.lua loads first in every TOC (the interrupt-ready unit rule).
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MSUF", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))("MSUF", ns)
    local refresh = Check(_G.MSUF_KickReady_RefreshFrame, "interrupt-ready refresh export is missing")
    local eventFrame = Check(named.MSUF_InterruptReady_EventFrame, "interrupt-ready event frame is missing")

    -- Horizontal geometry, in bar pixels from the left edge.
    local function FillRect(bar)
        local minimum, maximum, value = Unwrap(bar.minimum), Unwrap(bar.maximum), Unwrap(bar.value)
        local fraction = (value - minimum) / (maximum - minimum)
        if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end
        if bar.reverse then return WIDTH - fraction * WIDTH, WIDTH end
        return 0, fraction * WIDTH
    end
    local function RelativeRect(relative)
        if relative.fillOf then return FillRect(relative.fillOf) end
        return 0, WIDTH
    end
    local function X(point, relative, relativePoint, offset)
        local left, right = RelativeRect(relative)
        if relativePoint:find("LEFT") then return left + offset end
        if relativePoint:find("RIGHT") then return right + offset end
        return (left + right) / 2 + offset
    end
    local function Rect(region)
        if region.allPoints then return RelativeRect(region.allPoints) end
        local left, right, center
        for _, anchor in ipairs(region.points) do
            local x = X(anchor[1], anchor[2], anchor[3], anchor[4])
            if anchor[1]:find("LEFT") then left = x
            elseif anchor[1]:find("RIGHT") then right = x
            else center = x end
        end
        local width = region.width or 0
        if left and not right then right = left + width end
        if right and not left then left = right - width end
        if center then left, right = center - width / 2, center + width / 2 end
        return Check(left, "unanchored region"), right
    end
    local function Visible(region, bar)
        if not region.shown or (region.alpha or 1) <= 0 then return false end
        local left, right = Rect(region)
        for _, mask in ipairs(region.masks) do
            if mask.allPoints == bar then
                left, right = math.max(left, 0), math.min(right, WIDTH)
            end
        end
        return right - left > 0.001
    end

    local function Castbar(reverse, countsDown)
        local frame = { unit = "target", MSUF_castActive = true, isNotInterruptible = false,
            MSUF_kickInterruptibleConfirmed = true, _msufStripeReverseFill = reverse, _msufCountsDown = countsDown }
        frame.statusBar = CreateFrame("StatusBar", nil, UIParent)
        frame.statusBar:SetStatusBarTexture("bar")
        frame.castText = frame.statusBar:CreateFontString(nil, "OVERLAY")
        return frame
    end
    -- Where the cast bar's moving edge is at time fraction t of the cast.
    local function EdgeAt(t, reverse, countsDown)
        local reach = countsDown and (1 - t) or t
        if reverse then return WIDTH - reach * WIDTH end
        return reach * WIDTH
    end

    local function CheckCase(reverse, countsDown, secret, label)
        kickEnd = 103
        local start, finish = 100, 110
        local frame = Castbar(reverse, countsDown)
        frame.MSUF_durationObj = {
            GetStartTime = function() return secret and Secret(start) or start end,
            GetEndTime = function() return secret and Secret(finish) or finish end,
        }
        if secret then
            cooldownFactory = function()
                return { GetEndTime = function() return Secret(kickEnd) end,
                    GetRemainingDuration = function() return Secret(kickEnd - 100) end }
            end
            frame._msufApiNotInterruptibleRaw = Secret(false)
        else
            cooldownFactory = function()
                return { GetEndTime = function() return kickEnd end, GetRemainingDuration = function() return kickEnd - 100 end }
            end
        end
        refresh(frame)
        local projection = Check(frame._msufKickTimeProjections and frame._msufKickTimeProjections[1], label .. ": no projection")
        local marker, segment = projection.marker, projection.segment
        local bar = frame.statusBar
        if secret then
            Check(IsSecret(projection.minimum) and IsSecret(projection.maximum) and IsSecret(projection.value),
                label .. ": restricted times did not reach the native sinks unchanged")
        end
        Check(marker.parent == bar and segment.parent == bar, label .. ": marker and shade are not regions of the castbar's bar")
        Check(marker.layer ~= "OVERLAY" and segment.layer ~= "OVERLAY", label .. ": marker or shade draws above the cast text")
        local recover = (kickEnd - start) / (finish - start)
        local edge = EdgeAt(recover, reverse, countsDown)
        local mLeft, mRight = Rect(marker)
        Check(Visible(marker, bar) and mLeft <= edge + 0.001 and edge - 0.001 <= mRight,
            label .. ": marker at " .. mLeft .. ".." .. mRight .. " misses the edge position " .. edge)
        local sLeft, sRight = Rect(segment)
        local finalEdge = EdgeAt(1, reverse, countsDown)
        Check(math.abs(sLeft - math.min(edge, finalEdge)) < 0.001 and math.abs(sRight - math.max(edge, finalEdge)) < 0.001,
            label .. ": shade covers " .. sLeft .. ".." .. sRight .. ", not the time after recovery")
        -- An unchanged refresh rewrites only the value sinks.
        writes = 0
        local valueWrites = projection.valueWrites
        refresh(frame)
        local expectedWrites = secret and 2 or 0
        Check(writes == expectedWrites, label .. ": unchanged refresh rewrote " .. writes .. " layout properties")
        Check(projection.valueWrites - valueWrites == 2, label .. ": unchanged refresh did not rewrite exactly the value sinks")
        -- Recovering only after the cast ends leaves nothing to mark.
        kickEnd = 112
        refresh(frame)
        Check(not Visible(marker, bar), label .. ": marker pinned to the bar end although the interrupt recovers after the cast")
        Check(not Visible(segment, bar), label .. ": shade shown although the interrupt recovers after the cast")
        -- A cooldown reduction arrives as a cooldown event with an unchanged
        -- ready state; the recovery point still moves.
        kickEnd = 104
        eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 6552)
        kickEnd = 102
        eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 6552)
        Check(Unwrap(projection.value) == 102, label .. ": cooldown reduction left the marker on the old recovery time")
        -- Teardown hides every piece.
        frame.MSUF_castActive = false
        refresh(frame)
        Check(not projection.shown and not marker.shown and not segment.shown, label .. ": projection survived cast teardown")
        return frame, projection
    end

    CheckCase(false, false, false, "cast")
    CheckCase(true, false, false, "reverse-filled cast")
    CheckCase(false, true, false, "draining channel")
    CheckCase(true, true, false, "reverse-filled draining channel")
    CheckCase(false, false, true, "restricted cast")
    CheckCase(false, true, true, "restricted draining channel")

    -- Rounded or slanted bars mask their fill; the projection borrows it.
    do
        kickEnd = 103
        cooldownFactory = function() return { GetEndTime = function() return kickEnd end, GetRemainingDuration = function() return 3 end } end
        local frame = Castbar(false, false)
        frame.MSUF_durationObj = { GetStartTime = function() return 100 end, GetEndTime = function() return 110 end }
        local rounded = frame.statusBar:CreateMaskTexture()
        frame.statusBar:GetStatusBarTexture():AddMaskTexture(rounded)
        refresh(frame)
        local projection = frame._msufKickTimeProjections[1]
        local function Has(region, mask)
            for _, existing in ipairs(region.masks) do if existing == mask then return true end end
            return false
        end
        Check(Has(projection.marker, rounded) and Has(projection.segment, rounded), "projection ignores the bar's shape mask")
        frame.statusBar:GetStatusBarTexture():RemoveMaskTexture(rounded)
        refresh(frame)
        Check(not Has(projection.marker, rounded) and not Has(projection.segment, rounded), "projection kept a released shape mask")
    end
end

print("castbar_time_axis_smoke: interrupt projection OK")
