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
}
local LIMITS = {
    width = { 40, 1200 }, height = { 4, 100 }, scale = { 50, 200 }, opacity = { 0, 100 },
    x = { -2000, 2000 }, y = { -1200, 1200 }, backgroundOpacity = { 0, 100 },
    borderSize = { 0, 8 }, fontSize = { 6, 72 }, textX = { -300, 300 }, textY = { -200, 200 },
}
local frames, byType = {}, {}
local active, preview, driver, nativeEnabled, formatter

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
end
local function BindTimer(frame)
    local cfg = frame.config
    local direction = cfg.fill == "remaining" and _G.Enum.StatusBarTimerDirection.RemainingTime
        or _G.Enum.StatusBarTimerDirection.ElapsedTime
    if cfg.display == "bar" then
        frame.Bar:SetTimerDuration(frame.duration, _G.Enum.StatusBarInterpolation.Immediate, direction)
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

local function HideNative(frame)
    if active and frame:IsShown() then frame:Hide() end
end
local function SuppressNative()
    if _G.GetCVarBool("showSwingTimer") then _G.SetCVar("showSwingTimer", "0") end
    for i = 1, #HANDS do
        local frame = _G["SwingTimer" .. NAMES[HANDS[i]] .. "Frame"]
        if frame then
            if not frame._msufSwingHideHook then
                frame._msufSwingHideHook = true
                frame:HookScript("OnShow", HideNative)
            end
            HideNative(frame)
        end
    end
end
local function RefreshVisibility()
    local main, off, ranged = _G.UnitAttackSpeed("player")
    local listen = false
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        local cfg = frame.config
        if i == 1 then frame.speed = main elseif i == 2 then frame.speed = off else frame.speed = ranged end
        local equipped = i == 1 or (frame.speed and frame.speed > 0)
        frame.handlesSwings = cfg.enabled and equipped == true
        if frame.handlesSwings and not preview then listen = true end
        local shown = active and cfg.enabled and (preview or (equipped
            and (cfg.visibility == "always" or _G.UnitAffectingCombat("player"))))
        frame:SetShown(shown == true)
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
end

local function OnEvent(_, event, a, b)
    if event == "PLAYER_SWING" then
        local frame = byType[b]
        if frame and frame.handlesSwings then Start(frame, a) end
    elseif event == "PLAYER_LOGOUT" then
        -- Restore the account CVar before a reload as well as when disabling.
        active = false
        _G.SetCVar("showSwingTimer", nativeEnabled and "1" or "0")
    elseif event == "CVAR_UPDATE" then
        if active and a == "showSwingTimer" then SuppressNative() end
    elseif event == "ADDON_LOADED" then
        if a == "Blizzard_SwingTimer" then SuppressNative() end
    else
        if event == "PLAYER_REGEN_DISABLED" then preview = false end
        RefreshVisibility()
        if event == "WEAPON_SLOT_CHANGED" then
            for i = 1, #HANDS do
                local frame = frames[HANDS[i]]
                if frame.endsAt and frame.endsAt > _G.GetTime() then Start(frame, frame.speed) end
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
    SuppressNative()
    RefreshVisibility()
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
    driver.listening = nil
    for i = 1, #HANDS do
        local frame = frames[HANDS[i]]
        Stop(frame)
        frame:Hide()
        frame:EnableMouse(false)
    end
    _G.SetCVar("showSwingTimer", nativeEnabled and "1" or "0")
    for i = 1, #HANDS do
        local frame = _G["SwingTimer" .. NAMES[HANDS[i]] .. "Frame"]
        if frame then frame:UpdateShownStateAndRegistration() end
    end
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
    if active then RefreshVisibility() end
    return true
end
function Swing.GetPreview() return preview == true end
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
