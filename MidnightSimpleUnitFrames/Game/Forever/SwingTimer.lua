-- Forever supplies swing events; MSUF owns the bars and profile settings.
-- Reference: upstream/forever Blizzard_SwingTimer and Blizzard_CustomAuraButton.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...)
    if type(policy) == "string" then return region[policy](region, ...) end
    return region
end
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
local active, preview, driver, nativeEnabled, formatter
-- Attacks that replace the next melee swing, by class. The client answers by
-- spell name, so every rank matches.
local NEXT_SWING = { WARRIOR = { 78, 845 }, DRUID = { 6807 }, HUNTER = { 2973 } }
-- Every next-swing attack in menu order, for the per-attack cue texts.
local NEXT_SWING_ORDER = { 78, 845, 6807, 2973 }
local CUE_LABEL_LIMIT = 40
local cueNames, cueIcons, cueLabelKeys, cueSpell, cueTitled = {}, {}, {}, nil, false
local cueEventsBound, reachEventsBound, equippedOff, equippedRanged = false, false, nil, nil
local Public = _G.issecretvalue and function(value) return not _G.issecretvalue(value) end or function() return true end
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

local function DB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    if type(db.swingTimers) ~= "table" then
        -- Migrate the previous native master switch once.
        db.swingTimers = { enabled = (active and nativeEnabled or _G.GetCVarBool("showSwingTimer")) == true }
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
    return _G.Enum and _G.Enum.PlayerSwingType ~= nil
        and _G.C_DurationUtil and type(_G.C_DurationUtil.CreateDurationTextBinding) == "function"
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
    local lsm = MSUF.LSM or _G.MSUF_LSM
    return (lsm and lsm:Fetch("statusbar", key, true)) or fallback
end
local function Stop(frame)
    frame.endsAt = nil
    frame.duration:Reset()
    frame.binding:SetEnabled(false)
    frame.Time:SetText("0.0")
    frame.Bar:SetTimerDuration(frame.duration)
    frame.Bar:SetValue(0)
    if frame.Lane then frame.Lane:SetTimerDuration(frame.duration); frame.Lane:SetValue(0) end
end
local function BindTimer(frame)
    local cfg = frame.config
    local direction = cfg.fill == "remaining" and _G.Enum.StatusBarTimerDirection.RemainingTime
        or _G.Enum.StatusBarTimerDirection.ElapsedTime
    if cfg.display == "bar" then
        frame.Bar:SetTimerDuration(frame.duration, _G.Enum.StatusBarInterpolation.Immediate, direction)
    end
    if frame.Lane and frames.main.config.offhandLane and frames.main.config.display == "bar" then
        local main = frames.main.config
        local laneDirection = main.fill == "remaining" and _G.Enum.StatusBarTimerDirection.RemainingTime
            or _G.Enum.StatusBarTimerDirection.ElapsedTime
        frame.Lane:SetTimerDuration(frame.duration, _G.Enum.StatusBarInterpolation.Immediate, laneDirection)
    end
    frame.binding:SetDuration(frame.duration)
    frame.binding:SetEnabled((cfg.time or cfg.display == "text") and frame:IsShown())
end
local function Start(frame, duration)
    if not duration or duration <= 0 then Stop(frame); return end
    frame.endsAt = _G.GetTime() + duration
    frame.duration:SetTimeFromEnd(frame.endsAt, duration)
    BindTimer(frame)
end
local function OnDragStart(frame)
    if preview and not _G.InCombatLockdown() then frame:StartMoving() end
end
local function OnDragStop(frame)
    frame:StopMovingOrSizing()
    if not preview then return end
    local x, y = frame:GetCenter()
    local parentX, parentY = _G.UIParent:GetCenter()
    local scale = frame:GetScale()
    frame.config.x = math.floor(x * scale - parentX + 0.5)
    frame.config.y = math.floor(y * scale - parentY + 0.5)
    Swing.Apply()
    local menu = MSUF.MSUF2
    if menu and menu.activeKey == "swingtimers" and menu.Refresh and Swing.menuContext then
        menu.Refresh(Swing.menuContext)
    end
end

local function CreateSurface(frame)
    local bar = PixelLayoutRegion(_G.CreateFrame("StatusBar", nil, frame))
    bar:SetMinMaxValues(0, 1)
    bar.Background = PixelLayoutRegion(bar:CreateTexture(nil, "BACKGROUND"))
    bar.Background:SetAllPoints()
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

local function CreateBar(hand)
    local frame = PixelLayoutRegion(_G.CreateFrame("Frame", "MSUF_SwingTimer_" .. hand, _G.UIParent, "BackdropTemplate"))
    frame.hand = hand
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)
    frame.Bar = CreateSurface(frame)
    frame.Text = PixelLayoutRegion(_G.CreateFrame("Frame", nil, frame))
    frame.Text:SetAllPoints()
    frame.Text:SetFrameLevel(frame.Bar:GetFrameLevel() + 2)
    frame.Title = PixelLayoutRegion(frame.Text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    frame.Title:SetPoint("LEFT", 5, 0)
    frame.Title:SetJustifyH("LEFT")
    frame.Time = PixelLayoutRegion(frame.Text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    frame.duration = _G.C_DurationUtil.CreateDuration()
    frame.binding = _G.C_DurationUtil.CreateDurationTextBinding()
    frame.binding:SetFontString(frame.Time)
    frame.binding:SetUpdateInterval(0.1)
    frame.binding:SetExpiredText("0.0")
    frame.binding:SetZeroDurationText("0.0")
    if not formatter then
        formatter = _G.C_StringUtil.CreateNumericRuleFormatter()
        formatter:SetBreakpoints({ { threshold = 0, step = 0.1,
            rounding = _G.Enum.NumericRuleFormatRounding.Nearest, format = "%.1f" } })
    end
    frame.binding:SetTextFormat("{}", {
        { property = _G.Enum.DurationTextBindingProperty.RemainingDuration, formatter = formatter },
    })
    Stop(frame)
    frame:Hide()
    frames[hand] = frame
    byType[_G.Enum.PlayerSwingType[NAMES[hand]]] = frame
    return frame
end

-- Blizzard owns its bars' visibility through the showSwingTimer CVar: its own
-- CVarCallbackRegistry handler runs UpdateFrameState on every bar
-- (Blizzard_SwingTimer.lua OnShowSwingTimerCVarChanged), so turning the CVar
-- off hides them and restoring it shows them again. Showing or hiding a bar
-- from addon code would run the bottom managed-frame container layout (which
-- also places ExtraAbilityContainer) tainted. Only Blizzard's Edit Mode shows a
-- bar while the CVar is off (ShouldBeShown: isInEditMode); that one case is
-- hidden here. Hooked bars are kept in a side table, never on Blizzard's frame.
local nativeHooked = setmetatable({}, { __mode = "k" })
local function HideNative(frame)
    if active and frame.isInEditMode and frame:IsShown() then frame:Hide() end
end
local function SuppressNative()
    if _G.GetCVarBool("showSwingTimer") then _G.SetCVar("showSwingTimer", "0") end
    for i = 1, #HANDS do
        local frame = _G["SwingTimer" .. NAMES[HANDS[i]] .. "Frame"]
        if frame then
            if not nativeHooked[frame] then
                nativeHooked[frame] = true
                frame:HookScript("OnShow", HideNative)
            end
            HideNative(frame)
        end
    end
end
local function RefreshVisibility()
    local main, off, ranged = _G.UnitAttackSpeed("player")
    equippedOff, equippedRanged = Equipped(off), Equipped(ranged)
    local listen = false
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        local cfg = frame.config
        if i == 1 then frame.speed = main elseif i == 2 then frame.speed = off else frame.speed = ranged end
        local equipped = i == 1 or (frame.speed ~= nil and Equipped(frame.speed))
        frame.handlesSwings = cfg.enabled and equipped == true
        if frame.handlesSwings and not preview then listen = true end
        local shown = active and cfg.enabled and (preview or (equipped
            and (cfg.visibility == "always" or _G.UnitAffectingCombat("player"))))
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
        elseif frame.endsAt and frame.endsAt > _G.GetTime() then
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
-- colour. Written only when the state flips; the lane inherits main's alpha.
local function PaintReach(frame)
    local c = frame.config
    local outside = c.reachCheck == true and frame.outside == true and not preview
    if frame.reachShown == outside then return end
    frame.reachShown = outside
    frame:SetAlpha(c.opacity / 100 * (outside and c.reachOpacity / 100 or 1))
    frame.Bar:SetStatusBarColor(unpack(outside and c.reachColor or c.color))
end
-- C_SwingTimer.EnableRangeCheck is one switch per hand shared with Blizzard's
-- bars, which turn it off when their CVar drops: force re-asserts it.
local function SyncRanges(force)
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        local enabled = (active and frame.handlesSwings and frame.config.reachCheck and not preview) and true or false
        local swingType = _G.Enum.PlayerSwingType[NAMES[frame.hand]]
        if force or enabled ~= frame.rangeEnabled then
            frame.rangeEnabled = enabled
            _G.C_SwingTimer.EnableRangeCheck(swingType, enabled)
        end
        local range = enabled and _G.C_SwingTimer.IsTargetWithinSwingRange(swingType)
        frame.outside = enabled and Public(range) and range == false or false
        PaintReach(frame)
    end
end
local function SyncReachEvents()
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
    else
        driver:UnregisterEvent("PLAYER_TARGET_CHANGED")
        driver:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
    end
end
-- Spell names and icons are static: read once per apply, never per event.
local function ResolveCue()
    for i = #cueNames, 1, -1 do cueNames[i] = nil end
    local _, class = _G.UnitClass("player")
    local list = NEXT_SWING[class]
    local spellAPI = _G.C_Spell
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
        local isCurrent = _G.C_Spell.IsCurrentSpell
        for i = 1, #cueNames do
            local answer = isCurrent(cueNames[i])
            if Public(answer) and answer then current = cueNames[i]; break end
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
local function StyleLane()
    local main, off = frames.main, frames.off
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
    local font = cfg.font ~= "" and cfg.font or (_G.MSUF_GetFontPath and _G.MSUF_GetFontPath()) or _G.STANDARD_TEXT_FONT
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

local function Style(frame, cfg)
    frame.config = cfg
    frame:SetSize(cfg.width, cfg.height)
    frame:SetScale(cfg.scale / 100)
    frame:SetAlpha(cfg.opacity / 100)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", _G.UIParent, "CENTER", cfg.x / frame:GetScale(), cfg.y / frame:GetScale())
    local inset = math.min(cfg.borderSize, (cfg.height - 1) / 2, (cfg.width - 1) / 2)
    PixelLayoutRegion(frame, "SetBackdrop", cfg.display == "bar" and cfg.borderSize > 0 and {
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = inset,
    } or nil)
    frame:SetBackdropBorderColor(unpack(cfg.borderColor))
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
        cueSpell, cueTitled = nil, false
    end
end

local function OnEvent(_, event, a, b, c)
    if event == "PLAYER_SWING" then
        local frame = byType[b]
        if frame and frame.handlesSwings then Start(frame, a) end
    elseif event == "PLAYER_LOGOUT" then
        -- Restore the account CVar before a reload as well as when disabling.
        active = false
        _G.SetCVar("showSwingTimer", nativeEnabled and "1" or "0")
    elseif event == "CVAR_UPDATE" then
        if active and a == "showSwingTimer" then SuppressNative(); SyncRanges(true) end
    elseif event == "ADDON_LOADED" then
        if a == "Blizzard_SwingTimer" then SuppressNative() end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local frame = byType[a]
        if frame then
            frame.outside = frame.rangeEnabled == true and Public(c) and c == true and Public(b) and b == false or false
            PaintReach(frame)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        SyncRanges()
    elseif event == "CURRENT_SPELL_CAST_CHANGED" or event == "ACTIONBAR_UPDATE_STATE" then
        UpdateCue()
    elseif event == "UNIT_ATTACK_SPEED" then
        -- Haste procs change the speeds many times a minute; only equipping or
        -- removing an off-hand or ranged weapon changes which bars run.
        local _, off, ranged = _G.UnitAttackSpeed("player")
        if Equipped(off) ~= equippedOff or Equipped(ranged) ~= equippedRanged then
            RefreshVisibility()
            SyncRanges()
        end
    else
        if event == "PLAYER_REGEN_DISABLED" then preview = false end
        RefreshVisibility()
        SyncRanges()
        if event == "PLAYER_REGEN_DISABLED" then UpdateCue() end
        if event == "WEAPON_SLOT_CHANGED" then
            -- A secret speed cannot rebind the duration (SetTimeFromEnd takes
            -- plain numbers only); the running swing keeps its timer.
            for i = 1, #HANDS do
                local frame = frames[HANDS[i]]
                if frame.endsAt and frame.endsAt > _G.GetTime() and Public(frame.speed) then
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
    StyleLane()
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
    nativeEnabled = _G.GetCVarBool("showSwingTimer")
    active = true
    if not driver then driver = _G.CreateFrame("Frame") end
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
end
local function Disable()
    if not active then return end
    active, preview = false, false
    driver:UnregisterAllEvents()
    driver.listening, cueEventsBound, reachEventsBound = nil, false, false
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        Stop(frame)
        frame:Hide()
        frame:EnableMouse(false)
        if frame.rangeEnabled then _G.C_SwingTimer.EnableRangeCheck(_G.Enum.PlayerSwingType[NAMES[frame.hand]], false) end
        frame.rangeEnabled, frame.outside, frame.reachShown = false, false, nil
        if frame.Lane then frame.Lane:Hide() end
    end
    if frames.main and frames.main.Cue then frames.main.Cue:Hide() end
    cueSpell, cueTitled = nil, false
    -- Blizzard's CVar callback shows its bars and re-registers PLAYER_SWING.
    _G.SetCVar("showSwingTimer", nativeEnabled and "1" or "0")
end
function Swing.SetEnabled(value)
    local cfg = DB()
    if not cfg or _G.InCombatLockdown() then return false end
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
    if key:find("^nextSwingLabel") and #value > CUE_LABEL_LIMIT then return false end
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
    if value and (not active or _G.InCombatLockdown()) then return false end
    preview = value == true
    if preview then
        for i = 1, #HANDS do Stop(frames[HANDS[i]]) end
    end
    if active then RefreshVisibility(); SyncRanges(); UpdateCue() end
    return true
end
function Swing.GetPreview() return preview == true end
-- The next-swing attacks with a cue text, in menu order: spell ID, the
-- client's spell name (nil when the client has none) and the setting key.
function Swing.CueAttacks()
    local list, spellAPI = {}, _G.C_Spell
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

-- Initial profile binding does not run the profile-change module fanout. Start
-- once after PLAYER_LOGIN has bound the profile, also on /reload. Reuse the
-- runtime driver; a disabled module drops this subscription immediately.
if not active then
    driver = driver or _G.CreateFrame("Frame")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self:SetScript("OnEvent", nil)
        MSUF.MSUF_ApplyModules()
    end)
end
