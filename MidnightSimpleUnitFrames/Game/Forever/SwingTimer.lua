-- Forever supplies swing events; MSUF owns the bars and profile settings.
-- Reference: upstream/forever Blizzard_SwingTimer and Blizzard_CustomAuraButton.
local _, MSUF = ...
if not MSUF.Client.IsForever then return end
local FILE = "Game/Forever/SwingTimer.lua"
local Require = MSUF.Require
local PixelLayoutRegion = Require("MSUF_PixelLayoutRegion", FILE)
local issecretvalue = issecretvalue
local Swing = {}
MSUF.SwingTimer = Swing
local HANDS = { "main", "off", "ranged" }
local NAMES = { main = "MainHand", off = "OffHand", ranged = "Ranged" }
local LABELS = { main = "Main Hand", off = "Off Hand", ranged = "Ranged" }
local DEFAULTS = {
    enabled = true, visibility = "always", width = 260, height = 18,
    scale = 100, opacity = 100, x = 0, y = -220, texture = "MSUF Smooth",
    backgroundTexture = "", backgroundOpacity = 65, borderSize = 1,
    title = true, time = true, font = "", fontSize = 12, outline = "OUTLINE",
    display = "bar", direction = "RIGHT", fill = "elapsed", color = { 0.85, 0.65, 0.25 },
    textAlign = "AUTO", textX = 0, textY = 0,
    backgroundColor = { 0.08, 0.08, 0.08 }, borderColor = { 0, 0, 0 },
    textColor = { 1, 1, 1 },
    -- Main hand only: the off-hand lane and the next-swing cue. The cue can also
    -- name the queued attack on the bar: its spell name, or the text set here
    -- for that attack (one entry per next-swing attack below, empty = name).
    offhandLane = false, nextSwingCue = true, nextSwingColor = { 0.35, 0.8, 1 },
    nextSwingText = false, nextSwingLabel78 = "", nextSwingLabel845 = "",
    nextSwingLabel6807 = "", nextSwingLabel2973 = "",
    -- Every hand: grey the bar while the target is out of that weapon's reach.
    reachCheck = false, reachOpacity = 70, reachColor = { 0.55, 0.55, 0.6 },
}
local LIMITS = {
    width = { 40, 1200 }, height = { 4, 100 }, scale = { 50, 200 }, opacity = { 0, 100 },
    x = { -2000, 2000 }, y = { -1200, 1200 }, backgroundOpacity = { 0, 100 },
    borderSize = { 0, 8 }, fontSize = { 6, 72 }, textX = { -300, 300 }, textY = { -200, 200 },
    reachOpacity = { 0, 100 },
}
local frames, byType = {}, {}
local active, preview, manualPreview, editPreview, driver, nativeEnabled, formatter
local rangedSpellID, rangeTicker
local RANGE_INTERVAL = 0.2
-- Duel interaction distance is a short-range fallback when auto-attack range is unavailable.
local DUEL_DISTANCE = 3
local CheckInteractDistance = CheckInteractDistance
local NewTicker = C_Timer and C_Timer.NewTicker
local meleeRangeUnavailable
-- Same equipped-weapon shots as Blizzard's Forever hostile targeting bar.
local AUTO_SHOT = 75
local WEAPON_SHOTS = { Bows = 2480, Guns = 7918, Thrown = 2764, Crossbow = 7919, Wand = 5019 }
-- Attacks that replace the next melee swing, by class. The client answers by
-- spell name, so every rank matches.
local NEXT_SWING = { WARRIOR = { 78, 845 }, DRUID = { 6807 }, HUNTER = { 2973 } }
-- Every next-swing attack in menu order, for the per-attack cue texts.
local NEXT_SWING_ORDER = { 78, 845, 6807, 2973 }
local CUE_LABEL_LIMIT = 40
local cueNames, cueIcons, cueLabelKeys, cueSpell, cueTitled = {}, {}, {}, nil, false
local cueEventsBound, reachEventsBound, equippedOff, equippedRanged = false, false, nil, nil
local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end
-- UnitAttackSpeed is SecretWhenUnitStatsRestricted. A hand without a weapon
-- answers nil; a secret speed is a returned speed, so its weapon is equipped.
local function Equipped(speed)
    if not Public(speed) then return true end
    return (speed or 0) > 0
end

-- Settings saved under the former names of the swing extras move over once
-- (the former key is removed); the queued-attack text was always on with them.
local FORMER = {
    combineOffhand = "offhandLane", rangeWarning = "reachCheck", rangeAlpha = "reachOpacity",
    rangeColor = "reachColor", queuedAttack = "nextSwingCue", queuedColor = "nextSwingColor",
    heroicText = "nextSwingLabel78", cleaveText = "nextSwingLabel845", maulText = "nextSwingLabel6807",
}
local function CarryFormer(bar)
    if bar.queuedAttack ~= nil and bar.nextSwingText == nil then bar.nextSwingText = bar.queuedAttack == true end
    for former, current in pairs(FORMER) do
        if bar[former] ~= nil then bar[current], bar[former] = bar[former], nil end
    end
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    return { value[1], value[2], value[3] }
end

local function ProfileDB()
    return MSUF_DB
end
local function DB()
    local db = ProfileDB()
    if type(db) ~= "table" then return nil end
    if type(db.swingTimers) ~= "table" then
        -- Migrate the previous native master switch once.
        db.swingTimers = { enabled = (active and nativeEnabled or GetCVarBool("showSwingTimer")) == true }
    end
    local cfg = db.swingTimers
    for i = 1, #HANDS do
        local hand = HANDS[i]
        if type(cfg[hand]) ~= "table" then cfg[hand] = {} end
        local bar = cfg[hand]
        if bar.direction == nil then bar.direction = bar.reverse and "LEFT" or "RIGHT" end
        if bar.queuedAttack ~= nil or bar.combineOffhand ~= nil or bar.rangeWarning ~= nil then CarryFormer(bar) end
        for key, value in pairs(DEFAULTS) do
            if bar[key] == nil then
                if key == "y" then bar[key] = value - (i - 1) * 26
                elseif key == "enabled" then bar[key] = hand ~= "ranged"
                else bar[key] = Copy(value) end
            end
        end
    end
    return cfg
end

function Swing.IsAvailable()
    return Enum and Enum.PlayerSwingType ~= nil
        and C_DurationUtil and type(C_DurationUtil.CreateDurationTextBinding) == "function"
end
function Swing.GetEnabled()
    local cfg = DB()
    return cfg and cfg.enabled == true or false
end
function Swing.Get(hand, key)
    local cfg = DB()
    return cfg and cfg[hand] and cfg[hand][key]
end

-- Resolve the exact asset used by the menu preview, without a Castbars dependency.
-- The shared choices include built-ins that need not be registered in SharedMedia.
local texturePaths
function Swing.ResolveTexture(key, fallback)
    if not key or key == "" then return fallback end
    if key:find("\\", 1, true) or key:find("/", 1, true) then return key end
    if not texturePaths then
        texturePaths = {}
        local choices = MSUF.UI and MSUF.UI.StatusBarTextureItems
        if choices then
            for _, item in ipairs(choices()) do texturePaths[item.value] = item.texture end
        end
    end
    local texture = texturePaths[key]
    if texture then return texture end
    local lsm = MSUF.LSM or Require("MSUF_LSM", FILE)
    return lsm:Fetch("statusbar", key, true) or fallback
end
local function Stop(frame)
    frame.endsAt = nil
    frame.duration:Reset()
    frame.binding:SetEnabled(false)
    frame.Time:SetText("0.0")
    frame.Bar:SetTimerDuration(frame.duration)
    frame.Bar:SetValue(0)
    if frame.Lane then
        frame.Lane:SetTimerDuration(frame.duration)
        frame.Lane:SetValue(0)
    end
end
local function BindTimer(frame)
    local cfg = frame.config
    local direction = cfg.fill == "remaining" and Enum.StatusBarTimerDirection.RemainingTime
        or Enum.StatusBarTimerDirection.ElapsedTime
    if cfg.display == "bar" then
        frame.Bar:SetTimerDuration(frame.duration, Enum.StatusBarInterpolation.Immediate, direction)
    end
    if frame.Lane and frames.main.config.offhandLane and frames.main.config.display == "bar" then
        local main = frames.main.config
        local laneDirection = main.fill == "remaining" and Enum.StatusBarTimerDirection.RemainingTime
            or Enum.StatusBarTimerDirection.ElapsedTime
        frame.Lane:SetTimerDuration(frame.duration, Enum.StatusBarInterpolation.Immediate, laneDirection)
    end
    frame.binding:SetDuration(frame.duration)
    frame.binding:SetEnabled((cfg.time or cfg.display == "text") and frame:IsShown())
end
local function Start(frame, duration)
    if not duration or duration <= 0 then
        Stop(frame)
        return
    end
    frame.endsAt = GetTime() + duration
    frame.duration:SetTimeFromEnd(frame.endsAt, duration)
    BindTimer(frame)
end
local function OnDragStart(frame)
    if preview and not InCombatLockdown() then
        frame.dragging = true
        frame:StartMoving()
    end
end
local function OnDragStop(frame)
    if not frame.dragging then return end
    frame.dragging = nil
    frame:StopMovingOrSizing()
    if not preview or InCombatLockdown() then return end
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    local scale = frame:GetScale()
    frame.config.x = math.floor(x * scale - parentX + 0.5)
    frame.config.y = math.floor(y * scale - parentY + 0.5)
    Swing.Apply()
    local menu = MSUF.MSUF2
    if menu and menu.activeKey == "swingtimers" and menu.Refresh and Swing.menuContext then
        menu.Refresh(Swing.menuContext)
    end
end

local function CreateSurface(frame, backgroundParent)
    local bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, frame))
    bar:SetMinMaxValues(0, 1)
    bar.Background = PixelLayoutRegion((backgroundParent or bar):CreateTexture(nil, "BACKGROUND"))
    bar.Background:SetAllPoints(bar)
    return bar
end

local function StyleSurface(bar, cfg, inset, texture)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", inset, -inset)
    bar:SetPoint("BOTTOMRIGHT", -inset, inset)
    bar:SetStatusBarTexture(texture)
    local fillTexture = bar:GetStatusBarTexture()
    if fillTexture then
        fillTexture:SetHorizTile(false)
        fillTexture:SetVertTile(false)
    end
    bar:SetStatusBarColor(unpack(cfg.color))
    local vertical = cfg.direction == "UP" or cfg.direction == "DOWN"
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetRotatesTexture(vertical)
    bar:SetReverseFill(cfg.direction == "LEFT" or cfg.direction == "DOWN")
    bar.Background:SetTexture(Swing.ResolveTexture(cfg.backgroundTexture, texture))
    bar.Background:SetVertexColor(unpack(cfg.backgroundColor))
    bar.Background:SetAlpha(cfg.backgroundOpacity / 100)
end

local function CreateBar(hand, parent)
    local sample = parent ~= nil
    local frame = PixelLayoutRegion(CreateFrame("Frame", not sample and "MSUF_SwingTimer_" .. hand or nil,
        parent or UIParent, "BackdropTemplate"))
    frame.hand = hand
    if not sample then
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", OnDragStart)
        frame:SetScript("OnDragStop", OnDragStop)
    end
    if sample then
        frame.PreviewBorder = PixelLayoutRegion(CreateFrame("Frame", nil, frame, "BackdropTemplate"))
        frame.PreviewBorder:SetAllPoints()
    end
    frame.Bar = CreateSurface(frame, sample and frame)
    frame.Text = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    frame.Text:SetAllPoints()
    frame.Text:SetFrameLevel(frame.Bar:GetFrameLevel() + 2)
    frame.Title = PixelLayoutRegion(frame.Text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    frame.Title:SetPoint("LEFT", 5, 0)
    frame.Title:SetJustifyH("LEFT")
    frame.Time = PixelLayoutRegion(frame.Text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    -- Menu samples share the surfaces, but never bind native timers or register
    -- as gameplay bars. Missing profile values resolve without migrating the DB.
    if sample then
        frame.previewConfig = setmetatable({}, { __index = function(_, key)
            local value = frame.previewSource and frame.previewSource[key]
            if value ~= nil then return value end
            return DEFAULTS[key]
        end })
        return frame
    end
    frame.duration = C_DurationUtil.CreateDuration()
    frame.binding = C_DurationUtil.CreateDurationTextBinding()
    frame.binding:SetFontString(frame.Time)
    frame.binding:SetUpdateInterval(0.1)
    frame.binding:SetExpiredText("0.0")
    frame.binding:SetZeroDurationText("0.0")
    if not formatter then
        formatter = C_StringUtil.CreateNumericRuleFormatter()
        formatter:SetBreakpoints({ { threshold = 0, step = 0.1,
            rounding = Enum.NumericRuleFormatRounding.Nearest, format = "%.1f" } })
    end
    frame.binding:SetTextFormat("{}", {
        { property = Enum.DurationTextBindingProperty.RemainingDuration, formatter = formatter },
    })
    Stop(frame)
    frame:Hide()
    frames[hand] = frame
    byType[Enum.PlayerSwingType[NAMES[hand]]] = frame
    return frame
end

-- Blizzard owns its bars' visibility through the showSwingTimer CVar: its own
-- CVarCallbackRegistry handler runs UpdateFrameState on every bar
-- (Blizzard_SwingTimer.lua OnShowSwingTimerCVarChanged), so turning the CVar
-- off hides them and restoring it shows them again. Showing or hiding a bar
-- from addon code would run the bottom managed-frame container layout (which
-- also places ExtraAbilityContainer) tainted: the bars inherit
-- BottomManagedFrameTemplate, and their OnHide (EditModeSystemMixin
-- OnSystemHide) removes them from it. Only Blizzard's Edit Mode shows a bar
-- while the CVar is off (ShouldBeShown: isInEditMode); that one case is made
-- invisible here, never hidden: alpha 0 (the bar takes no mouse of its own),
-- the alpha Blizzard had set (Edit Mode opacity) kept for the release. Blizzard
-- hides the bar itself when Edit Mode ends. Hooked bars and their alpha live in
-- side tables, never on Blizzard's frame.
local nativeHooked = setmetatable({}, { __mode = "k" })
local nativeAlpha = setmetatable({}, { __mode = "k" })
local function MuteNative(frame)
    if not (active and frame.isInEditMode and frame:IsShown()) then return end
    local alpha = frame:GetAlpha()
    if alpha > 0 then
        nativeAlpha[frame] = alpha
        frame:SetAlpha(0)
    end
end
local function RestoreNative()
    for frame, alpha in pairs(nativeAlpha) do
        nativeAlpha[frame] = nil
        frame:SetAlpha(alpha)
    end
end
local function SuppressNative()
    if GetCVarBool("showSwingTimer") then SetCVar("showSwingTimer", "0") end
    for i = 1, #HANDS do
        local frame = _G["SwingTimer" .. NAMES[HANDS[i]] .. "Frame"]
        if frame then
            if not nativeHooked[frame] then
                nativeHooked[frame] = true
                frame:HookScript("OnShow", MuteNative)
            end
            MuteNative(frame)
        end
    end
end
local function ResolveRangedSpell()
    local cfg = frames.ranged.config
    if not (equippedRanged and cfg.enabled and cfg.reachCheck) then return end
    local book, spell, item = C_SpellBook, C_Spell, C_Item
    if not (book and book.IsSpellKnown and spell and spell.IsSpellInRange and item and item.GetItemInfoInstant
        and NewTicker and GetInventoryItemID and INVSLOT_RANGED) then return end
    local weapon = GetInventoryItemID("player", INVSLOT_RANGED)
    if not (Public(weapon) and weapon) then return end
    local _, class = UnitClass("player")
    if class == "HUNTER" then
        if book.IsSpellKnown(AUTO_SHOT) then return AUTO_SHOT end
        return
    end
    local _, _, _, _, _, itemClass, subclass = item.GetItemInfoInstant(weapon)
    if itemClass ~= Enum.ItemClass.Weapon or not subclass then return end
    for weaponType, spellID in pairs(WEAPON_SHOTS) do
        if subclass == Enum.ItemWeaponSubclass[weaponType] and book.IsSpellKnown(spellID) then return spellID end
    end
end

local function RefreshVisibility()
    local main, off, ranged = UnitAttackSpeed("player")
    equippedOff, equippedRanged = Equipped(off), Equipped(ranged)
    rangedSpellID = ResolveRangedSpell()
    local listen = false
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        local cfg = frame.config
        if i == 1 then frame.speed = main elseif i == 2 then frame.speed = off else frame.speed = ranged end
        -- Equipped asks issecretvalue first; Equipped(nil) is false.
        local equipped = i == 1 or Equipped(frame.speed)
        frame.handlesSwings = cfg.enabled and equipped == true
        if frame.handlesSwings and not preview then listen = true end
        local shown = active and cfg.enabled and (preview or (equipped
            and (cfg.visibility == "always" or UnitAffectingCombat("player"))))
        -- The off-hand lane draws the off-hand timer inside the main-hand bar.
        local lane = frame.hand == "off" and frames.main.config.offhandLane == true
            and frames.main.config.display == "bar" and frames.main.handlesSwings == true
        if lane then shown = false end
        frame:SetShown(shown == true)
        if frame.Lane then frame.Lane:SetShown(lane and frame.handlesSwings and frames.main:IsShown() or false) end
        frame:EnableMouse(preview == true and cfg.enabled)
        if not cfg.enabled or not equipped then Stop(frame) end
        local barShown = cfg.display == "bar"
        frame.Bar:SetShown(barShown and not preview)
        if preview and cfg.enabled then
            frame.binding:SetEnabled(false)
            if barShown and not frame.PreviewBar then
                -- A static surface never inherits the live native duration driver.
                frame.PreviewBar = CreateSurface(frame)
                StyleSurface(frame.PreviewBar, cfg, frame.inset, frame.texture)
            end
            if frame.PreviewBar then frame.PreviewBar:SetValue(cfg.fill == "remaining" and 0.35 or 0.65) end
            frame.Time:SetText("1.2")
        elseif frame.endsAt and frame.endsAt > GetTime() then
            BindTimer(frame)
        else
            Stop(frame)
        end
        if frame.PreviewBar then frame.PreviewBar:SetShown(preview and cfg.enabled and barShown or false) end
        if not shown then frame.binding:SetEnabled(false) end
    end
    -- Keep combat-only bars subscribed before their first swing reveals them.
    -- With no selected/equipped weapon, even the swing dispatcher is dormant.
    if listen ~= driver.listening then
        driver.listening = listen
        if listen then driver:RegisterEvent("PLAYER_SWING")
        else driver:UnregisterEvent("PLAYER_SWING") end
    end
end

-- Out of reach: the bar fades to the chosen opacity and takes the reach
-- colour. Written only when the state flips.
local function StyleReach(frame, outside)
    local c = frame.config
    frame:SetAlpha(c.opacity / 100 * (outside and c.reachOpacity / 100 or 1))
    frame.Bar:SetStatusBarColor(unpack(outside and c.reachColor or c.color))
end

local function PaintReach(frame)
    local c = frame.config
    local outside = c.reachCheck == true and frame.outside == true and not preview
    if frame.reachShown == outside then return end
    frame.reachShown = outside
    StyleReach(frame, outside)
    local main, off = frames.main, frames.off
    if frame.Lane then frame.Lane:SetStatusBarColor(unpack(outside and c.reachColor or c.color)) end
    if off.Lane and frame ~= frames.ranged then
        -- The lane already inherits the main-hand fade. Apply its own opacity only
        -- if the main hand is not faded, so the two range settings never stack.
        local fadeLane = off.reachShown and not main.reachShown
        off.Lane:SetAlpha(fadeLane and off.config.reachOpacity / 100 or 1)
    end
end
local function StopRangeTicker()
    if not rangeTicker then return end
    rangeTicker:Cancel()
    rangeTicker = nil
end

local function CanSampleTarget()
    local attackable = UnitCanAttack("player", "target")
    if not (Public(attackable) and attackable) then return false end
    local dead = UnitIsDeadOrGhost("target")
    return Public(dead) and not dead
end

local function SetReach(frame, outside)
    frame.outside = outside
    PaintReach(frame)
end

local function UpdateNativeReach(frame, range)
    if not frame.rangeEnabled or not Public(range) then
        frame.rangeFallback = false
        SetReach(frame, false)
        return
    end
    local fallback
    if frame.hand == "ranged" then
        fallback = rangedSpellID ~= nil
    else
        fallback = CheckInteractDistance ~= nil and NewTicker ~= nil and not meleeRangeUnavailable
    end
    frame.rangeFallback = range == nil and fallback
    if not frame.rangeFallback then SetReach(frame, range == false) end
end

local PollRanges
local function SampleFallbackRanges()
    local main, off, ranged = frames.main, frames.off, frames.ranged
    local melee = main.rangeFallback or off.rangeFallback
    if not (melee or ranged.rangeFallback) then
        StopRangeTicker()
        return
    end

    local target = CanSampleTarget()
    local poll = false
    if melee then
        local outside = false
        if target then
            local range = CheckInteractDistance("target", DUEL_DISTANCE)
            if Public(range) then
                poll = range ~= nil
                outside = range == false
            end
        end
        if main.rangeFallback then SetReach(main, outside) end
        if off.rangeFallback then SetReach(off, outside) end
        if target and not poll then
            -- No answer for this target. A target or state event can retry it.
            meleeRangeUnavailable = true
            main.rangeFallback, off.rangeFallback = false, false
        end
    end
    if ranged.rangeFallback then
        local outside = false
        if target then
            local range = C_Spell.IsSpellInRange(rangedSpellID)
            outside = Public(range) and range == false
            poll = true
        end
        SetReach(ranged, outside)
    end
    if poll then
        if not rangeTicker then rangeTicker = NewTicker(RANGE_INTERVAL, PollRanges) end
    else
        StopRangeTicker()
    end
end

PollRanges = function()
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        if frame.rangeFallback then
            UpdateNativeReach(frame, C_SwingTimer.IsTargetWithinSwingRange(Enum.PlayerSwingType[NAMES[frame.hand]]))
        end
    end
    SampleFallbackRanges()
end

-- C_SwingTimer.EnableRangeCheck is one switch per hand shared with Blizzard's
-- bars, which turn it off when their CVar drops: force re-asserts it.
local function SyncRanges(force)
    meleeRangeUnavailable = nil
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        local shown = frame:IsShown() or (frame.Lane and frame.Lane:IsShown())
        local enabled = (active and shown and frame.config.reachCheck and not preview) and true or false
        local swingType = Enum.PlayerSwingType[NAMES[frame.hand]]
        if force or enabled ~= frame.rangeEnabled then
            frame.rangeEnabled = enabled
            C_SwingTimer.EnableRangeCheck(swingType, enabled)
        end
        local range = enabled and C_SwingTimer.IsTargetWithinSwingRange(swingType)
        UpdateNativeReach(frame, range)
    end
    SampleFallbackRanges()
end
local function SyncReachEvents()
    local ranged = frames.ranged.config
    if ranged.enabled and ranged.reachCheck then
        driver:RegisterEvent("SPELLS_CHANGED")
        driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    else
        driver:UnregisterEvent("SPELLS_CHANGED")
        driver:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end
    local want = false
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        if active and frame.config.enabled and frame.config.reachCheck then want = true end
    end
    if want == reachEventsBound then return end
    reachEventsBound = want
    if want then
        driver:RegisterEvent("PLAYER_TARGET_CHANGED")
        driver:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
        driver:RegisterUnitEvent("UNIT_FACTION", "target")
        driver:RegisterUnitEvent("UNIT_FLAGS", "target")
    else
        driver:UnregisterEvent("PLAYER_TARGET_CHANGED")
        driver:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
        driver:UnregisterEvent("UNIT_FACTION")
        driver:UnregisterEvent("UNIT_FLAGS")
    end
end
-- Spell names and icons are static: read once per apply, never per event.
local function ResolveCue()
    for i = #cueNames, 1, -1 do cueNames[i] = nil end
    local _, class = UnitClass("player")
    local list = NEXT_SWING[class]
    local spellAPI = C_Spell
    if not (list and spellAPI and spellAPI.GetSpellName) then return end
    for i = 1, #list do
        local name = spellAPI.GetSpellName(list[i])
        if Public(name) and type(name) == "string" then
            cueNames[#cueNames + 1] = name
            cueIcons[name] = spellAPI.GetSpellTexture and spellAPI.GetSpellTexture(list[i]) or nil
            cueLabelKeys[name] = "nextSwingLabel" .. list[i]
        end
    end
end
-- A queued next-swing attack shows its icon beside the main-hand bar and
-- tints the bar's border; with the cue text on, the bar's title names it in
-- the cue colour. Written only when the queued attack changes.
local function UpdateCue()
    local main = frames.main
    if not main then return end
    local c = main.config
    local current
    if c.nextSwingCue and c.display == "bar" and not preview then
        local isCurrent = C_Spell.IsCurrentSpell
        for i = 1, #cueNames do
            local answer = isCurrent(cueNames[i])
            if Public(answer) and answer then
                current = cueNames[i]
                break
            end
        end
    end
    if current == cueSpell then return end
    cueSpell = current
    if current then
        main.Cue:SetTexture(cueIcons[current])
        main.Cue:Show()
        main:SetBackdropBorderColor(unpack(c.nextSwingColor))
        if c.nextSwingText then
            local label = c[cueLabelKeys[current]]
            main.Title:SetText(type(label) == "string" and label ~= "" and label or current)
            main.Title:SetTextColor(unpack(c.nextSwingColor))
            main.Title:Show()
            cueTitled = true
        end
    else
        main.Cue:Hide()
        main:SetBackdropBorderColor(unpack(c.borderColor))
    end
    if cueTitled and not (current and c.nextSwingText) then
        cueTitled = false
        main.Title:SetText((MSUF.L and MSUF.L[LABELS.main]) or LABELS.main)
        main.Title:SetTextColor(unpack(c.textColor))
        main.Title:SetShown(c.title and c.display == "bar")
    end
end
local function SyncCueEvents()
    local main = frames.main
    local want = (active and main and main.config.enabled and main.config.nextSwingCue and #cueNames > 0) and true or false
    if want == cueEventsBound then return end
    cueEventsBound = want
    if want then
        driver:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
        driver:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    else
        driver:UnregisterEvent("CURRENT_SPELL_CAST_CHANGED")
        driver:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
    end
end
-- The off-hand lane: a strip along the main-hand bar's far edge (its right
-- side when vertical) in the off-hand bar's own colour.
local function StyleLane(main, off)
    local cfg = main.config
    if not (cfg.offhandLane and cfg.display == "bar") then
        if off.Lane then off.Lane:Hide() end
        return
    end
    if not off.Lane then off.Lane = CreateSurface(main) end
    local lane, inset = off.Lane, main.inset
    local vertical = cfg.direction == "UP" or cfg.direction == "DOWN"
    local thickness = math.max(2, math.floor(((vertical and cfg.width or cfg.height) - 2 * inset) / 3 + 0.5))
    lane:ClearAllPoints()
    if vertical then
        lane:SetPoint("TOPRIGHT", main, "TOPRIGHT", -inset, -inset)
        lane:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -inset, inset)
        lane:SetWidth(thickness)
    else
        lane:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", inset, inset)
        lane:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -inset, inset)
        lane:SetHeight(thickness)
    end
    lane:SetFrameLevel(main.Bar:GetFrameLevel() + 1)
    lane:SetStatusBarTexture(main.texture)
    lane:SetStatusBarColor(unpack(off.config.color))
    lane:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    lane:SetRotatesTexture(vertical)
    lane:SetReverseFill(cfg.direction == "LEFT" or cfg.direction == "DOWN")
    lane.Background:SetTexture(main.texture)
    lane.Background:SetVertexColor(0, 0, 0)
    lane.Background:SetAlpha(0.5)
end

local function StyleFonts(frame, cfg)
    local font = cfg.font ~= "" and cfg.font or Require("MSUF_GetFontPath", FILE)() or STANDARD_TEXT_FONT
    frame.Title:SetFont(font, cfg.fontSize, cfg.outline)
    frame.Time:SetFont(font, cfg.fontSize, cfg.outline)
    frame.Title:SetTextColor(unpack(cfg.textColor))
    frame.Time:SetTextColor(unpack(cfg.textColor))
end

function Swing.ApplyFonts()
    if not active then return end
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        if frame and frame.config.font == "" then StyleFonts(frame, frame.config) end
    end
end

local function Place(frame)
    local cfg, scale = frame.config, frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.x / scale, cfg.y / scale)
end

local function CancelDrag(frame)
    if not frame.dragging then return end
    frame.dragging = nil
    frame:StopMovingOrSizing()
    Place(frame)
end

local function Style(frame, cfg, sample)
    frame.config = cfg
    frame:SetSize(cfg.width, cfg.height)
    frame:SetScale(cfg.scale / 100)
    frame:SetAlpha(cfg.opacity / 100)
    if not sample then Place(frame) end
    local inset = math.min(cfg.borderSize, (cfg.height - 1) / 2, (cfg.width - 1) / 2)
    local border = frame.PreviewBorder or frame
    PixelLayoutRegion(border, "SetBackdrop", cfg.display == "bar" and cfg.borderSize > 0 and {
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = inset,
    } or nil)
    border:SetBackdropBorderColor(unpack(cfg.borderColor))
    frame.inset = inset
    frame.texture = Swing.ResolveTexture(cfg.texture, "Interface\\TargetingFrame\\UI-StatusBar")
    StyleSurface(frame.Bar, cfg, inset, frame.texture)
    if frame.PreviewBar then StyleSurface(frame.PreviewBar, cfg, inset, frame.texture) end
    StyleFonts(frame, cfg)
    frame.Title:SetWidth(math.max(1, cfg.width - (cfg.time and cfg.fontSize * 4 or 10)))
    frame.Title:SetText((MSUF.L and MSUF.L[LABELS[frame.hand]]) or LABELS[frame.hand])
    frame.Title:SetShown(cfg.title and cfg.display == "bar")
    frame.Time:SetShown(cfg.time or cfg.display == "text")
    local align = cfg.textAlign
    if align == "AUTO" then align = cfg.display == "text" and "CENTER" or "RIGHT" end
    local padding = cfg.display == "bar" and (align == "LEFT" and 5 or align == "RIGHT" and -5 or 0) or 0
    frame.Time:ClearAllPoints()
    frame.Time:SetPoint(align, frame.Text, align, padding + cfg.textX, cfg.textY)
    frame.Time:SetJustifyH(align)
    frame.reachShown = nil
    if frame.hand == "main" then
        if not frame.Cue then
            frame.Cue = PixelLayoutRegion(frame.Text:CreateTexture(nil, "OVERLAY"))
            frame.Cue:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        frame.Cue:SetSize(cfg.height, cfg.height)
        frame.Cue:ClearAllPoints()
        frame.Cue:SetPoint("RIGHT", frame, "LEFT", -2, 0)
        frame.Cue:Hide()
        if not sample then cueSpell, cueTitled = nil, false end
    end
end

function Swing.CreateMenuPreview(parent, hand)
    if not parent or not LABELS[hand] then return end
    return CreateBar(hand, parent)
end

function Swing.PaintMenuPreview(samples, outsideHand)
    local db = ProfileDB()
    local cfg = db and db.swingTimers
    for i = 1, #HANDS do
        local hand = HANDS[i]
        local frame = samples[hand]
        frame.previewSource = cfg and cfg[hand]
        local values = frame.previewConfig
        Style(frame, values, true)
        frame.Bar:SetShown(values.display == "bar")
        frame.Bar.Background:SetShown(values.display == "bar")
        frame.Bar:SetValue(values.fill == "remaining" and 0.35 or 0.65)
        if hand == outsideHand then StyleReach(frame, true) end
        frame.Time:SetText("1.2")
    end
    local main, off = samples.main, samples.off
    StyleLane(main, off)
    if off.Lane then
        off.Lane:SetShown(main.config.offhandLane and main.config.display == "bar" and off.config.enabled)
        off.Lane:SetValue(main.config.fill == "remaining" and 0.35 or 0.65)
    end
end

local function SyncPreview()
    local wanted = active == true and (manualPreview == true or editPreview == true)
    if wanted == (preview == true) then return end
    preview = wanted
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        if wanted then Stop(frame) else CancelDrag(frame) end
    end
    RefreshVisibility()
    SyncRanges()
    UpdateCue()
end

local function EditModeChanged(value)
    editPreview = value == true
    SyncPreview()
end

local function OnEvent(_, event, a, b, c)
    if event == "PLAYER_SWING" then
        local frame = byType[b]
        if frame and frame.handlesSwings then Start(frame, a) end
    elseif event == "PLAYER_LOGOUT" then
        StopRangeTicker()
        -- Restore the account CVar before a reload as well as when disabling.
        active = false
        SetCVar("showSwingTimer", nativeEnabled and "1" or "0")
    elseif event == "CVAR_UPDATE" then
        if active and a == "showSwingTimer" then
            SuppressNative()
            SyncRanges(true)
        end
    elseif event == "ADDON_LOADED" then
        if a == "Blizzard_SwingTimer" then
            SuppressNative()
            SyncRanges(true)
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local frame = Public(a) and byType[a]
        if frame and frame.rangeEnabled then
            local wasFallback = frame.rangeFallback
            if not Public(c) then
                UpdateNativeReach(frame, c)
            elseif c then
                UpdateNativeReach(frame, b)
            else
                UpdateNativeReach(frame, nil)
            end
            if wasFallback ~= frame.rangeFallback then SampleFallbackRanges() end
        end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        if event == "PLAYER_EQUIPMENT_CHANGED" and a ~= INVSLOT_RANGED then return end
        rangedSpellID = ResolveRangedSpell()
        SyncRanges()
    elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" or event == "PLAYER_TARGET_CHANGED" then
        SyncRanges()
    elseif event == "CURRENT_SPELL_CAST_CHANGED" or event == "ACTIONBAR_UPDATE_STATE" then
        UpdateCue()
    elseif event == "UNIT_ATTACK_SPEED" then
        -- Haste procs change the speeds many times a minute; only equipping or
        -- removing an off-hand or ranged weapon changes which bars run.
        local _, off, ranged = UnitAttackSpeed("player")
        if Equipped(off) ~= equippedOff or Equipped(ranged) ~= equippedRanged then
            RefreshVisibility()
            SyncRanges()
        end
    else
        if event == "PLAYER_REGEN_DISABLED" and preview then
            manualPreview, editPreview = false, false
            SyncPreview()
            return
        end
        RefreshVisibility()
        SyncRanges()
        if event == "PLAYER_REGEN_DISABLED" then UpdateCue() end
        if event == "WEAPON_SLOT_CHANGED" then
            -- A secret speed cannot rebind the duration (SetTimeFromEnd takes
            -- plain numbers only); the running swing keeps its timer.
            for i = 1, #HANDS do
                local frame = frames[HANDS[i]]
                if frame.endsAt and frame.endsAt > GetTime() and Public(frame.speed) then
                    Start(frame, frame.speed)
                end
            end
        end
    end
end

function Swing.Apply()
    if not active then return end
    local cfg = DB()
    for i = 1, #HANDS do
        local hand = HANDS[i]
        Style(frames[hand] or CreateBar(hand), cfg[hand])
    end
    StyleLane(frames.main, frames.off)
    SuppressNative()
    ResolveCue()
    SyncCueEvents()
    SyncReachEvents()
    RefreshVisibility()
    SyncRanges(true)
    UpdateCue()
end
local function Enable()
    if active or not Swing.IsAvailable() then return end
    nativeEnabled = GetCVarBool("showSwingTimer")
    active = true
    if not driver then driver = CreateFrame("Frame") end
    driver:SetScript("OnEvent", OnEvent)
    driver:RegisterEvent("PLAYER_IN_COMBAT_CHANGED")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("WEAPON_SLOT_CHANGED")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:RegisterEvent("ADDON_LOADED")
    driver:RegisterEvent("CVAR_UPDATE")
    driver:RegisterEvent("PLAYER_LOGOUT")
    driver:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    Swing.Apply()
    SyncPreview()
end
local function Disable()
    if not active then return end
    active, preview, manualPreview = false, false, false
    StopRangeTicker()
    driver:UnregisterAllEvents()
    driver.listening, cueEventsBound, reachEventsBound = nil, false, false
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        CancelDrag(frame)
        Stop(frame)
        frame:Hide()
        frame:EnableMouse(false)
        if frame.rangeEnabled then C_SwingTimer.EnableRangeCheck(Enum.PlayerSwingType[NAMES[frame.hand]], false) end
        frame.rangeEnabled, frame.rangeFallback, frame.outside, frame.reachShown = false, false, false, nil
        if frame.Lane then frame.Lane:Hide() end
    end
    if frames.main and frames.main.Cue then frames.main.Cue:Hide() end
    cueSpell, cueTitled = nil, false
    -- Blizzard's CVar callback shows its bars and re-registers PLAYER_SWING;
    -- a bar muted in Edit Mode gets its alpha back first.
    RestoreNative()
    SetCVar("showSwingTimer", nativeEnabled and "1" or "0")
end
function Swing.SetEnabled(value)
    local cfg = DB()
    if not cfg or InCombatLockdown() then return false end
    cfg.enabled = value == true
    MSUF.MSUF_ApplyModules()
    return true
end
function Swing.Set(hand, key, value)
    local cfg = DB()
    if not cfg or not NAMES[hand] or DEFAULTS[key] == nil then return false end
    local limit = LIMITS[key]
    if limit then
        value = tonumber(value)
        if not value or value ~= value or value < limit[1] or value > limit[2] then return false end
        value = math.floor(value + 0.5)
    elseif type(DEFAULTS[key]) == "boolean" then value = value == true
    elseif type(DEFAULTS[key]) == "table" then
        if type(value) ~= "table" then return false end
        for i = 1, 3 do
            if type(value[i]) ~= "number" or value[i] ~= value[i] or value[i] < 0 or value[i] > 1 then return false end
        end
        value = Copy(value)
    elseif type(value) ~= "string" then return false end
    -- The limit counts characters: a UTF-8 continuation byte starts none.
    if key:find("^nextSwingLabel") and #value:gsub("[\128-\191]", "") > CUE_LABEL_LIMIT then return false end
    if key == "visibility" and value ~= "always" and value ~= "combat" then return false end
    if key == "fill" and value ~= "elapsed" and value ~= "remaining" then return false end
    if key == "display" and value ~= "bar" and value ~= "text" then return false end
    if key == "direction" and value ~= "RIGHT" and value ~= "LEFT" and value ~= "UP" and value ~= "DOWN" then return false end
    if key == "textAlign" and value ~= "AUTO" and value ~= "LEFT" and value ~= "CENTER" and value ~= "RIGHT" then return false end
    if key == "outline" and value ~= "" and value ~= "OUTLINE" and value ~= "THICKOUTLINE" then return false end
    cfg[hand][key] = value
    Swing.Apply()
    return true
end
function Swing.SetPreview(value)
    if value and (not active or InCombatLockdown()) then return false end
    manualPreview = value == true
    SyncPreview()
    return true
end
function Swing.GetPreview() return manualPreview == true end
-- The next-swing attacks with a cue text, in menu order: spell ID, the
-- client's spell name (nil when the client has none) and the setting key.
function Swing.CueAttacks()
    local list, spellAPI = {}, C_Spell
    for i = 1, #NEXT_SWING_ORDER do
        local id = NEXT_SWING_ORDER[i]
        local name = spellAPI and spellAPI.GetSpellName and spellAPI.GetSpellName(id)
        if not (Public(name) and type(name) == "string") then name = nil end
        list[i] = { id = id, name = name, key = "nextSwingLabel" .. id }
    end
    return list
end
function Swing.RefreshSettings()
    MSUF.MSUF_ApplyModules()
    Swing.Apply()
end
MSUF.MSUF_RegisterModule("SwingTimers", {
    order = 75, IsEnabled = Swing.GetEnabled, Enable = Enable, Disable = Disable,
    RefreshSettings = Swing.Apply, Shutdown = Disable,
})

Require("MSUF_RegisterAnyEditModeListener", FILE)(EditModeChanged)

-- Initial profile binding does not run the profile-change module fanout. Start
-- once after PLAYER_LOGIN has bound the profile, also on /reload. Reuse the
-- runtime driver; a disabled module drops this subscription immediately.
if not active then
    driver = driver or CreateFrame("Frame")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self:SetScript("OnEvent", nil)
        MSUF.MSUF_ApplyModules()
    end)
end
