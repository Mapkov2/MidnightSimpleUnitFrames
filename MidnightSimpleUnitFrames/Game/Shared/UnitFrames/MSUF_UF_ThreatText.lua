--- Threat percentage text on the target, focus and boss frames, and on the party
--- and raid frames.
---
--- A unit frame shows how much of the aggro threshold the player holds on the
--- frame's unit: the scaled percentage of UnitDetailedThreatSituation("player",
--- unit), where 100% means the player has aggro or takes it with the next hit.
--- Blizzard's own target frame reads the same call for its threat number on every
--- client. A group frame shows its member's scaled threat on the player's current
--- target, the number a threat meter lists.
---
--- Classic Era and TBC return plain numbers. WoW Forever runs the 12.1.5 secret
--- rules: the call is SecretWhenUnitThreatValuesRestricted, which keeps a normal
--- mob plain and makes a boss secret. A secret value is never compared here; two
--- secret-safe C string functions format it instead.
---
--- Offered on Classic Era, TBC and WoW Forever only (owner decision 2026-09-19).
--- The Mists manifest never lists this file, and on Midnight, which shares the
--- Mainline manifest with Forever, the client gate below returns before anything
--- is registered.
local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
-- Only an explicit "no" stops the file, so a harness without the client model
-- still gets the element.
if MSUF.Client and MSUF.Client.SupportsThreatText == false then return end
local UF = MSUF.UF
if not (UF and type(UF.RegisterElement) == "function") then return end

local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitThreatSituation = _G.UnitThreatSituation
local UnitExists = _G.UnitExists
local UnitCanAttack = _G.UnitCanAttack
local IsSecret = _G.issecretvalue
-- Both accept secret numbers from addon code (SecretArguments AllowedWhenTainted):
-- TruncateWhenZero floors to an integer and returns "" at zero, WrapString adds
-- the suffix only around a non-empty string, so a zero threat stays blank.
local stringUtil = _G.C_StringUtil
local TruncateWhenZero = type(stringUtil) == "table" and stringUtil.TruncateWhenZero or nil
local WrapString = type(stringUtil) == "table" and stringUtil.WrapString or nil
local type = type
local tonumber = tonumber
local pairs = pairs
local floor = math.floor

local EMPTY_EVENTS = {}
-- Fires on the frame's own unit token whenever the mob's threat list changes,
-- including the wipe when it dies or combat ends. Blizzard's nameplates and the
-- MSUF aggro border read threat on this event too.
local THREAT_EVENTS = { "UNIT_THREAT_LIST_UPDATE" }
-- One read after combat clears a number whose last list event never reached
-- this unit token.
local THREAT_LIFECYCLE_EVENTS = { "PLAYER_REGEN_ENABLED" }
local SAMPLE_VALUE = 85
local DEFAULT_ANCHOR = "BOTTOMLEFT"
-- Anchor -> horizontal justify, the same rule the other status texts follow
-- (MSUF_UF_Elements_Status.lua LayoutRegion). Name-relative anchors are not
-- offered for this text, so an unknown value falls back to the default.
local JUSTIFY_FOR_ANCHOR = {
    TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT",
    TOP = "CENTER", CENTER = "CENTER", BOTTOM = "CENTER",
    TOPRIGHT = "RIGHT", RIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
}
-- Group frames repaint together at most this often; Blizzard's own target frame
-- polls its threat number on the same half-second clock.
local GROUP_PASS_SECONDS = 0.5
-- A unit frame paints the first threat-list event at once and folds a burst into
-- one trailing paint, so a busy mob costs at most five reads a second per frame
-- (and a secret boss value at most five SetText calls).
local UNIT_PASS_SECONDS = 0.2
-- Every number the text can show, built once: a changing value costs a table
-- read, never a string build.
local PERCENT_TEXT = {}
for value = 0, 100 do PERCENT_TEXT[value] = value .. "%" end
-- Group refreshes re-apply elements by name (MSUF_UF_Group_Metadata.lua masks).
local GROUP_MASKS = { "MASK_FONT", "MASK_COLOR", "MASK_VISUAL", "MASK_RUNTIME" }
-- The dark plate behind the number (cfg.background). A threat color on a red
-- enemy bar has almost no contrast of its own; on the plate every curve color
-- reads. It is as wide as the widest value, "100%", in the text's own font: an
-- invisible sample string carries that size and the engine lays it out, so no
-- value is ever measured (a boss value on WoW Forever is secret) and the plate
-- keeps its width while the number grows.
local PLATE_SAMPLE = "100%"
local PLATE_PAD_X, PLATE_PAD_Y = 2, 1
local PLATE_ALPHA = 0.75
-- Anchor cache marker while the text is centred on the plate.
local PLATE_ANCHOR = "PLATE"

-- Color curve, low to high threat, blended linearly at 0%, 50% and 100%. The
-- palette is global (general.<key>R/G/B, unset = the default here) and shared by
-- every frame that colors its threat text by threat; Colors > Status Text Colors
-- and the ::: on the Threat % card edit the same keys. The 101 steps are computed
-- once per palette, so an event costs a table read and a write only on change.
local CURVE_STOPS = {
    { "threatColorLow", 0.30, 0.85, 0.30 },
    { "threatColorMid", 1.00, 0.82, 0.10 },
    -- Light pink rather than red: red digits vanish on red enemy bars (owner, 2026-09-19).
    { "threatColorHigh", 1.00, 0.60, 0.60 },
}
-- The stored R/G/B keys of each stop, built once.
local CURVE_KEYS = {}
for i = 1, #CURVE_STOPS do
    local key = CURVE_STOPS[i][1]
    CURVE_KEYS[i] = { key .. "R", key .. "G", key .. "B" }
end
local curveR, curveG, curveB = {}, {}, {}
local curvePalette = {}
-- Bumped on every rebuild; each text remembers the version it was painted with.
local curveVersion = 0

local Threat = { UpdateOnApply = true }

local function GeneralDB()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

-- A stop color counts only as a complete R/G/B triple, like the indicator colors.
local function StopRGB(general, i)
    local stop, keys = CURVE_STOPS[i], CURVE_KEYS[i]
    local r = tonumber(general and general[keys[1]])
    local g = tonumber(general and general[keys[2]])
    local b = tonumber(general and general[keys[3]])
    if r and g and b then return r, g, b end
    return stop[2], stop[3], stop[4]
end

local function EnsureCurve(general)
    local changed = curveR[0] == nil
    for i = 1, #CURVE_STOPS do
        local r, g, b = StopRGB(general, i)
        local base = (i - 1) * 3
        if curvePalette[base + 1] ~= r or curvePalette[base + 2] ~= g or curvePalette[base + 3] ~= b then
            curvePalette[base + 1], curvePalette[base + 2], curvePalette[base + 3] = r, g, b
            changed = true
        end
    end
    if not changed then return end
    local p = curvePalette
    for step = 0, 100 do
        local from, t = 0, step / 50
        if step > 50 then from, t = 3, (step - 50) / 50 end
        curveR[step] = p[from + 1] + (p[from + 4] - p[from + 1]) * t
        curveG[step] = p[from + 2] + (p[from + 5] - p[from + 2]) * t
        curveB[step] = p[from + 3] + (p[from + 6] - p[from + 3]) * t
    end
    curveVersion = curveVersion + 1
end

local function Config(frame, spec)
    spec = spec or (frame and frame.MSUFSpec)
    local status = spec and spec.status
    return status and status.threat or nil, status
end

-- Unit token -> the mob its threat is read against, or false. A frame's unit key
-- never changes, so each token is resolved once and a boss frame's read costs a
-- table lookup instead of a UF.IsBossUnit call.
local threatMob = { target = "target", focus = "focus" }
local function ThreatUnit(frame)
    local unit = frame and frame.MSUFUnitKey
    if type(unit) ~= "string" then return nil end
    local mob = threatMob[unit]
    if mob == nil then
        mob = type(UF.IsBossUnit) == "function" and UF.IsBossUnit(unit) and unit or false
        threatMob[unit] = mob
    end
    return mob or nil
end

local function ClampLayer(value)
    value = floor((tonumber(value) or 7) + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end

-- Only this file shows or hides the text, so its state is cached on the
-- FontString and a repeated event writes nothing. The plate, while in use,
-- follows the text.
local function SetShown(fs, show)
    if fs._msufThreatShown ~= show then
        if show then fs:Show() else fs:Hide() end
        fs._msufThreatShown = show
        local plate = fs._msufThreatPlate
        if plate then
            if show then plate:Show() else plate:Hide() end
        end
    end
end

-- Same parent and frame level as the status text holders in
-- MSUF_UF_Elements_Status.lua, so the text fades and stacks with them.
local function EnsureHolder(frame, layer)
    local holder = frame.threatIndicatorHolder
    if not holder then
        holder = CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame)
        holder:SetAllPoints(frame)
        if holder.EnableMouse then holder:EnableMouse(false) end
        if holder.SetClipsChildren then holder:SetClipsChildren(false) end
        frame.threatIndicatorHolder = holder
    end
    if holder.SetFrameLevel then
        local layers = UF.Layers
        local level = layers and layers.StatusLevel and layers.StatusLevel(frame, layer, 7)
            or (((layers and layers.BaseFrameLevel and layers.BaseFrameLevel(frame)) or 0) + 10 + layer)
        if holder._msufThreatFrameLevel ~= level then
            holder:SetFrameLevel(level)
            holder._msufThreatFrameLevel = level
        end
    end
    return holder
end

local function EnsureText(frame, layer)
    if not (frame and CreateFrame) then return nil end
    local holder = EnsureHolder(frame, layer)
    local fs = frame.threatIndicatorText
    if not fs then
        fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:Hide()
        fs._msufThreatShown = false
        frame.threatIndicatorText = fs
    end
    return fs
end

-- Built on first use: the plate draws on ARTWORK, below the text's OVERLAY, in
-- the same holder. The sample stays shown at alpha 0, so the engine keeps its
-- size current.
local function EnsurePlate(frame)
    local plate = frame.threatIndicatorPlate
    if not plate then
        local holder = frame.threatIndicatorHolder
        local sample = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sample:SetText(PLATE_SAMPLE)
        sample:SetAlpha(0)
        plate = holder:CreateTexture(nil, "ARTWORK")
        plate:SetColorTexture(0, 0, 0, PLATE_ALPHA)
        plate:SetPoint("TOPLEFT", sample, "TOPLEFT", -PLATE_PAD_X, PLATE_PAD_Y)
        plate:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", PLATE_PAD_X, -PLATE_PAD_Y)
        plate:Hide()
        plate._msufThreatSample = sample
        frame.threatIndicatorPlate = plate
    end
    return plate, plate._msufThreatSample
end

-- The sample copies whatever font the text ended up with, a refused font included.
local function MatchSampleFont(sample, fs)
    if not fs.GetFont then return end
    local file, height, flags = fs:GetFont()
    if file and (sample._msufThreatFont ~= file or sample._msufThreatFontSize ~= height
        or sample._msufThreatFontFlags ~= flags) then
        sample:SetFont(file, height, flags or "")
        sample._msufThreatFont, sample._msufThreatFontSize, sample._msufThreatFontFlags = file, height, flags
    end
end

-- Font face, flags and shadow follow the frame's compiled font like every other
-- status text; the size is the indicator's own. A refused font is retried once
-- per font epoch, when the font coordinator runs its next pass.
local function ApplyFont(fs, spec, size)
    local shared = UF.Shared
    size = shared and shared.ClampFontSize and shared.ClampFontSize(size, 11) or tonumber(size) or 11
    local font = spec and spec.font
    local flags = spec and spec.fontFlags or "OUTLINE"
    local epoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    if font and shared and shared.ApplyFontChecked
        and (fs._msufThreatFontAttempt ~= epoch or fs._msufThreatFont ~= font
            or fs._msufThreatFontSize ~= size or fs._msufThreatFontFlags ~= flags) then
        fs._msufThreatFont, fs._msufThreatFontSize, fs._msufThreatFontFlags = font, size, flags
        fs._msufThreatFontAttempt = epoch
        if not shared.ApplyFontChecked(fs, font, size, flags, 11) then
            local clear = _G.MSUF_ClearFontStringApplyCaches
            if type(clear) == "function" then clear(fs) end
            local markFailed = _G.MSUF_MarkFontApplyFailed
            if type(markFailed) == "function" then markFailed() end
        end
    end
    if fs.SetShadowOffset then
        local shadowOn = spec and spec.fontShadow == true
        local sx = shadowOn and (tonumber(spec.fontShadowX) or 1) or 0
        local sy = shadowOn and (tonumber(spec.fontShadowY) or -1) or 0
        local sa = shadowOn and (tonumber(spec.fontShadowAlpha) or 1) or 0
        if fs._msufThreatShadowX ~= sx or fs._msufThreatShadowY ~= sy or fs._msufThreatShadowA ~= sa then
            if shadowOn and fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, sa) end
            fs:SetShadowOffset(sx, sy)
            fs._msufThreatShadowX, fs._msufThreatShadowY, fs._msufThreatShadowA = sx, sy, sa
        end
    end
end

-- The frame's font color unless the indicator carries a complete color of its
-- own; alpha stays with the shared text alpha, as for the other status texts.
local function ApplyColor(fs, spec, cfg)
    local c = spec and spec.textColor
    local r, g, b, a = c and c.r or 1, c and c.g or 1, c and c.b or 1, c and c.a or 1
    if cfg.colorR and cfg.colorG and cfg.colorB then
        r, g, b = cfg.colorR, cfg.colorG, cfg.colorB
    end
    if fs._msufThreatR ~= r or fs._msufThreatG ~= g or fs._msufThreatB ~= b or fs._msufThreatA ~= a then
        fs:SetTextColor(r, g, b, a)
        fs._msufThreatR, fs._msufThreatG, fs._msufThreatB, fs._msufThreatA = r, g, b, a
    end
end

-- A curve color keeps the shared text alpha too. The curve step cache and the
-- static color cache clear each other, so switching the mode always repaints.
local function PaintStep(fs, step)
    if fs._msufThreatColorStep ~= step or fs._msufThreatCurveVersion ~= curveVersion then
        fs:SetTextColor(curveR[step], curveG[step], curveB[step], fs._msufThreatCurveAlpha or 1)
        fs._msufThreatColorStep, fs._msufThreatCurveVersion = step, curveVersion
        fs._msufThreatR = nil
    end
end

local function Layout(frame, fs, cfg, spec)
    local layer = ClampLayer(cfg.layer)
    EnsureHolder(frame, layer)
    ApplyFont(fs, spec, cfg.size)
    if cfg.colorCurve == true then
        EnsureCurve(GeneralDB())
        local c = spec and spec.textColor
        local a = c and c.a or 1
        if fs._msufThreatCurveAlpha ~= a then
            fs._msufThreatCurveAlpha = a
            fs._msufThreatColorStep = nil
        end
    else
        fs._msufThreatColorStep = nil
        ApplyColor(fs, spec, cfg)
    end
    local anchor = cfg.anchor
    local justify = JUSTIFY_FOR_ANCHOR[anchor]
    if not justify then
        anchor, justify = DEFAULT_ANCHOR, "LEFT"
    end
    local plated = cfg.background == true
    if plated then justify = "CENTER" end
    if fs._msufThreatJustify ~= justify then
        fs:SetJustifyH(justify)
        fs._msufThreatJustify = justify
    end
    local sublevel = layer - 1
    if sublevel > 7 then sublevel = 7 end
    if fs._msufThreatSublevel ~= sublevel then
        fs:SetDrawLayer("OVERLAY", sublevel)
        fs._msufThreatSublevel = sublevel
    end
    local alpha = spec and spec.status and spec.status.alpha or 1
    if fs._msufThreatAlpha ~= alpha then
        fs:SetAlpha(alpha)
        fs._msufThreatAlpha = alpha
    end
    local x, y = tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    local plate = frame.threatIndicatorPlate
    if plated then
        -- The sample takes the text's configured spot and the number is centred
        -- on it, so the plate sits where the text alone would.
        local sample
        plate, sample = EnsurePlate(frame)
        MatchSampleFont(sample, fs)
        if sample._msufThreatAnchor ~= anchor or sample._msufThreatX ~= x or sample._msufThreatY ~= y then
            sample:ClearAllPoints()
            sample:SetPoint(anchor, frame, anchor, x, y)
            sample._msufThreatAnchor, sample._msufThreatX, sample._msufThreatY = anchor, x, y
        end
        if fs._msufThreatAnchor ~= PLATE_ANCHOR then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", sample, "CENTER", 0, 0)
            fs._msufThreatAnchor, fs._msufThreatX, fs._msufThreatY = PLATE_ANCHOR, nil, nil
        end
        if plate._msufThreatAlpha ~= alpha then
            plate:SetAlpha(alpha)
            plate._msufThreatAlpha = alpha
        end
        fs._msufThreatPlate = plate
        if fs._msufThreatShown == true then plate:Show() else plate:Hide() end
        return
    end
    if plate then plate:Hide() end
    fs._msufThreatPlate = nil
    if fs._msufThreatAnchor ~= anchor or fs._msufThreatX ~= x or fs._msufThreatY ~= y then
        fs:ClearAllPoints()
        fs:SetPoint(anchor, frame, anchor, x, y)
        fs._msufThreatAnchor, fs._msufThreatX, fs._msufThreatY = anchor, x, y
    end
end

-- A plain number is cached, so only a changed percentage writes the text.
local function ShowValue(fs, value, curve)
    if fs._msufThreatValue ~= value then
        fs:SetText(PERCENT_TEXT[value] or (value .. "%"))
        fs._msufThreatValue = value
    end
    if curve then PaintStep(fs, value < 100 and value or 100) end
    SetShown(fs, true)
end

-- A secret number can neither be compared nor cached, so it is formatted on
-- every event; that only happens for a boss on WoW Forever. The curve cannot be
-- evaluated on a secret either (ColorCurve:Evaluate is AllowedWhenUntainted), so
-- the color follows the threat state, which stays readable for a boss: below
-- the tank = low, above the tank = medium, tanking = high.
local function ShowSecretValue(fs, scaled, curve, unit, mob)
    fs._msufThreatValue = nil
    if not (TruncateWhenZero and WrapString) then
        SetShown(fs, false)
        return
    end
    fs:SetText(WrapString(TruncateWhenZero(scaled), nil, "%"))
    if curve then
        local state = UnitThreatSituation and UnitThreatSituation(unit, mob)
        local step = 0
        if not (IsSecret and IsSecret(state) == true) then
            if state == 1 then step = 50 elseif state == 2 or state == 3 then step = 100 end
        end
        PaintStep(fs, step)
    end
    SetShown(fs, true)
end

-- Group frames: a mob's threat changes with UNIT_THREAT_LIST_UPDATE for that mob,
-- never with an event on the member, so one driver follows the player's target
-- for every group frame that shows the text and repaints them together. It only
-- listens while such a frame exists; with the option off it costs nothing.
local groupFrames = {}
local groupFrameCount = 0
local groupDriver
local groupPassPending = false
local lastGroupPass = -GROUP_PASS_SECONDS

local Paint

-- Only an attackable target can hold the group on its threat list. Any other
-- target (none, or a friend a healer clicks) clears the texts without a single
-- threat read. A secret answer counts as "maybe" and reads as before.
local function TargetHasThreatList()
    if UnitExists then
        local exists = UnitExists("target")
        if not (IsSecret and IsSecret(exists) == true) and not exists then return false end
    end
    if UnitCanAttack then
        local attackable = UnitCanAttack("player", "target")
        if not (IsSecret and IsSecret(attackable) == true) and not attackable then return false end
    end
    return true
end

local function RunGroupPass()
    groupPassPending = false
    lastGroupPass = GetTime and GetTime() or 0
    if not TargetHasThreatList() then
        for frame in pairs(groupFrames) do
            local fs = frame.threatIndicatorText
            if fs then SetShown(fs, false) end
        end
        return
    end
    for frame in pairs(groupFrames) do
        if frame.IsVisible and frame:IsVisible() then Paint(frame) end
    end
end

-- The first event after a quiet spell repaints at once; a burst collapses into
-- one trailing pass, so a pull costs at most two passes a second.
local function RequestGroupPass()
    if groupPassPending then return end
    local wait = lastGroupPass + GROUP_PASS_SECONDS - (GetTime and GetTime() or 0)
    if wait <= 0 or not (C_Timer and C_Timer.After) then
        RunGroupPass()
        return
    end
    groupPassPending = true
    C_Timer.After(wait, RunGroupPass)
end

local function SetGroupDriverListening(listen)
    if listen then
        if not groupDriver then
            groupDriver = CreateFrame("Frame")
            groupDriver:SetScript("OnEvent", RequestGroupPass)
        end
        groupDriver:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target")
        groupDriver:RegisterEvent("PLAYER_TARGET_CHANGED")
        groupDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif groupDriver then
        groupDriver:UnregisterAllEvents()
    end
end

local function AttachGroupFrame(frame)
    if groupFrames[frame] then return end
    groupFrames[frame] = true
    groupFrameCount = groupFrameCount + 1
    if groupFrameCount == 1 and CreateFrame then SetGroupDriverListening(true) end
end

local function DetachGroupFrame(frame)
    if not (frame and groupFrames[frame]) then return end
    groupFrames[frame] = nil
    groupFrameCount = groupFrameCount - 1
    if groupFrameCount <= 0 then
        groupFrameCount = 0
        SetGroupDriverListening(false)
    end
end

local function JoinGroupMasks()
    local gf = MSUF.GF
    if type(gf) ~= "table" then return end
    -- A group frame applies only the elements its base mask names
    -- (MSUF_UF_Group_Adapter.lua); without this the element never reaches a party
    -- or raid frame.
    local applyMask = gf.GROUP_APPLY_MASK
    if type(applyMask) == "table" then applyMask.ThreatIndicator = true end
    local metadata = gf.Metadata
    if type(metadata) ~= "table" then return end
    for i = 1, #GROUP_MASKS do
        local mask = metadata[GROUP_MASKS[i]]
        if type(mask) == "table" then mask.ThreatIndicator = true end
    end
end

function Threat.IsEnabled(frame, spec)
    local cfg, status = Config(frame, spec)
    if not (cfg and cfg.enabled == true and frame) then return false end
    return status.group == true or ThreatUnit(frame) ~= nil
end

function Threat.Apply(frame, spec)
    local cfg, status = Config(frame, spec)
    if not cfg then return end
    local fs = EnsureText(frame, ClampLayer(cfg.layer))
    if fs then Layout(frame, fs, cfg, spec or frame.MSUFSpec) end
    if status.group == true then
        -- A group test frame only ever shows the sample, so the driver skips it.
        if cfg.enabled == true and frame._msufGFIsPreviewFrame ~= true then
            AttachGroupFrame(frame)
        else
            DetachGroupFrame(frame)
        end
    end
end

-- Unit frames listen on their own unit; group frames ride the shared driver.
function Threat.GetEvents(frame, spec)
    local status = spec and spec.status
    if not status or status.testMode == true or status.group == true then return EMPTY_EVENTS end
    return THREAT_EVENTS
end

function Threat.GetUnitlessEvents(frame, spec)
    local status = spec and spec.status
    if not status or status.testMode == true or status.group == true then return EMPTY_EVENTS end
    return THREAT_LIFECYCLE_EVENTS
end

-- One threat read and cached writes: the whole cost of a shown text.
Paint = function(frame)
    local fs = frame and frame.threatIndicatorText
    if not fs then return end
    local spec = frame.MSUFSpec
    local status = spec and spec.status
    local cfg = status and status.threat
    if not (cfg and cfg.enabled == true) then
        SetShown(fs, false)
        return
    end
    local curve = cfg.colorCurve == true
    local unit, mob
    if status.group == true then
        -- Group test frames (Edit Mode, the group preview) show the sample, like
        -- unit test mode; live frames of the same kind keep their real value.
        if frame._msufGFIsPreviewFrame == true then
            ShowValue(fs, SAMPLE_VALUE, curve)
            return
        end
        unit, mob = frame.MSUFUnitKey, "target"
    else
        mob = ThreatUnit(frame)
        if mob and status.testMode == true then
            ShowValue(fs, SAMPLE_VALUE, curve)
            return
        end
        unit = "player"
    end
    if not (unit and mob) or type(UnitDetailedThreatSituation) ~= "function" then
        SetShown(fs, false)
        return
    end
    -- The third return is the scaled percentage (100 = aggro). Nothing comes back
    -- while the unit is not on the mob's threat list.
    local _, _, scaled = UnitDetailedThreatSituation(unit, mob)
    if IsSecret and IsSecret(scaled) == true then
        ShowSecretValue(fs, scaled, curve, unit, mob)
        return
    end
    if type(scaled) ~= "number" then
        SetShown(fs, false)
        return
    end
    -- Rounded down, like the secret path, so 100% only ever means aggro.
    local value = floor(scaled)
    if value <= 0 then
        SetShown(fs, false)
        return
    end
    ShowValue(fs, value, curve)
end

-- Unit frames whose threat-list events arrived inside their window, painted
-- together by one trailing timer.
local unitPending = {}
local unitFlushQueued = false

local function FlushUnitFrames()
    unitFlushQueued = false
    local now = GetTime()
    for frame in pairs(unitPending) do
        unitPending[frame] = nil
        frame._msufThreatPaintedAt = now
        Paint(frame)
    end
end

-- A threat-list event inside a unit frame's window waits for the shared trailing
-- paint. Everything else paints at once: the apply, a new target or boss, combat
-- end, test mode. Group frames never get the event; their driver paints them.
function Threat.Update(frame, event)
    if event == "UNIT_THREAT_LIST_UPDATE" and frame and GetTime and C_Timer and C_Timer.After then
        local now = GetTime()
        local last = frame._msufThreatPaintedAt
        if last and now - last < UNIT_PASS_SECONDS then
            if not unitPending[frame] then
                unitPending[frame] = true
                if not unitFlushQueued then
                    unitFlushQueued = true
                    C_Timer.After(last + UNIT_PASS_SECONDS - now, FlushUnitFrames)
                end
            end
            return
        end
        frame._msufThreatPaintedAt = now
    end
    Paint(frame)
end

function Threat.Disable(frame)
    local fs = frame and frame.threatIndicatorText
    if fs then SetShown(fs, false) end
    DetachGroupFrame(frame)
end

-- The menu reads the curve keys and defaults here (Colors page rows, ::: targets)
-- and the preview its sample color. Only clients that offer the threat text have it.
MSUF.UFThreatText = {
    CURVE_STOPS = CURVE_STOPS,
    CurveColorAt = function(general, percent)
        EnsureCurve(general)
        local step = floor(tonumber(percent) or 0)
        if step < 0 then step = 0 elseif step > 100 then step = 100 end
        return curveR[step], curveG[step], curveB[step]
    end,
}

-- identity: the value belongs to the bound mob or member, so a new target, focus,
-- boss or roster slot reseeds it through the core's identity path.
UF.RegisterElement("ThreatIndicator", Threat, {
    apply = true,
    events = true,
    defaultApply = true,
    identity = true,
})

_G.MSUF_RequestThreatIndicatorRefresh = function(unit, reason)
    if type(UF.RefreshElements) == "function" then
        return UF.RefreshElements(unit, { "ThreatIndicator" }, reason or "MSUF_THREAT_INDICATOR")
    end
    return false
end

-- Group frames apply elements by name: the base mask of MSUF_UF_Group_Adapter.lua
-- on every structural apply, the masks of MSUF_UF_Group_Metadata.lua on refreshes.
-- Both files load after this one and build their sets from literals, so the
-- element joins them once the whole addon has loaded.
JoinGroupMasks()
if CreateFrame then
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, loaded)
        if loaded ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        JoinGroupMasks()
    end)
end
