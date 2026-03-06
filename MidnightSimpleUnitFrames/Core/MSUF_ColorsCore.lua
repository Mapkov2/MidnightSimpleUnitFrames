-- MSUF_ColorsCore.lua
-- Runtime color logic: Get/Set/Reset for all color categories,
-- PushVisualUpdates, and mouseover-highlight system.
-- Loaded early (before Gameplay, Castbars, Borders etc.) so hot-path
-- consumers can call the getters at zero extra lookup cost.
-- The Options panel lives in MSUF_Options_Colors.lua.

local addonName, ns = ...
ns = ns or {}

------------------------------------------------------
-- Local shortcuts (core only — no UI-framework refs)
------------------------------------------------------
local EnsureDB              = _G.EnsureDB
local RAID_CLASS_COLORS     = RAID_CLASS_COLORS
local C_Timer               = C_Timer
local hooksecurefunc        = hooksecurefunc
local _G                    = _G

------------------------------------------------------
-- Helper: apply visual updates
------------------------------------------------------
local function PushVisualUpdates()
    if ns.MSUF_UpdateAllFonts then
        ns.MSUF_UpdateAllFonts()
    end
    if ns.MSUF_ApplyGameplayVisuals then
        ns.MSUF_ApplyGameplayVisuals()
    end
    if ns.MSUF_RefreshAllFrames then
        ns.MSUF_RefreshAllFrames()
    end

    -- Sync highlight priority stripe colors when border colors change.
    local reinit = _G.MSUF_PrioRows_Reinit
    if type(reinit) == "function" then reinit() end

    -- Live-update highlight border colors during test mode (zero cost when no test active).
    if _G.MSUF_AggroBorderTestMode or _G.MSUF_DispelBorderTestMode or _G.MSUF_PurgeBorderTestMode then
        local applyAll = _G.MSUF_ApplyBarOutlineThickness_All
        if type(applyAll) == "function" then applyAll() end
    end

    -- Safety: keep mouseover highlight bound to the correct unitframe.
    -- Throttled (coalesces rapid UI changes into 1 pass).
    if ns.MSUF_ScheduleMouseoverHighlightFix then
        ns.MSUF_ScheduleMouseoverHighlightFix()
    elseif ns.MSUF_FixMouseoverHighlightBindings then
        ns.MSUF_FixMouseoverHighlightBindings()
    end
end


------------------------------------------------------
-- Helper: ensure mouseover highlight border stays bound to its unitframe
-- (Prevents "floating highlight box" when the unitframe moves/hides.)
------------------------------------------------------
local function MSUF_GetHighlightObject(frame)
    if not frame then return nil end
    return frame.highlightBorder
        or frame.MSUF_highlightBorder
        or frame.MSUFHighlightBorder
        or frame.MSUF_highlight
        or frame.highlight
end


local function MSUF_FixHighlightForFrame(frame)
    local hb = MSUF_GetHighlightObject(frame)
    if not hb then return end

    -- Ensure the highlight is parented to the unitframe (so it moves/hides with it)
    if hb.GetParent and hb.SetParent and hb:GetParent() ~= frame then
        hb:SetParent(frame)
    end

    -- Ensure it is anchored to the unitframe (and includes the power bar if it extends below the main frame).
    -- Also try to snap to pixel grid to avoid "one side thicker" artifacts at non-integer UI scales.
    local bottomAnchor = frame
    -- When power bar is detached, highlight only covers the HP bar area.
    local pbDetached = frame._msufPowerBarDetached
    local pb = not pbDetached and (
        frame.targetPowerBar or frame.TargetPowerBar or frame.powerBar or frame.PowerBar
        or frame.power or frame.Power or frame.ManaBar or frame.manaBar
        or frame.MSUF_powerBar or frame.MSUF_PowerBar or frame.MSUFPowerBar
        or frame.resourceBar or frame.ResourceBar or frame.classPowerBar or frame.ClassPowerBar
    ) or nil

    if pb and pb.IsShown and pb.GetObjectType then
        -- Only use it if it behaves like a Region/Frame and is currently shown.
        local ok = true
        if pb.IsObjectType then
            ok = pb:IsObjectType("Frame") or pb:IsObjectType("StatusBar")
        end
        if ok and pb:IsShown() then
            bottomAnchor = pb
        end
    end

    -- If we didn't find a known power bar field, try a lightweight child scan by name.
    -- Skip scan when power bar is detached (highlight should only cover HP bar).
    if not pbDetached and bottomAnchor == frame and frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            local c = children[i]
            if c and c.IsShown and c.GetObjectType and c.IsObjectType then
                local okName, cname = MSUF_FastCall(c.GetName, c)
                if okName and type(cname) == "string" then
                    local lc = cname:lower()
                    if lc:find("power") or lc:find("mana") or lc:find("resource") then
                        if c:IsShown() and (c:IsObjectType("StatusBar") or c:IsObjectType("Frame")) then
                            bottomAnchor = c
                            break
                        end
                    end
                end
            end
        end
    end


    -- NOTE (Midnight secret-values): Do NOT use GetBottom()/GetTop() math here.
    -- We anchor to the power bar frame directly instead of computing screen-space extents.
    local yOff = 0

    if hb.ClearAllPoints then
        hb:ClearAllPoints()
    end

    if _G.PixelUtil and _G.PixelUtil.SetPoint then
        _G.PixelUtil.SetPoint(hb, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        _G.PixelUtil.SetPoint(hb, "BOTTOMRIGHT", bottomAnchor, "BOTTOMRIGHT", 0, yOff)
    elseif hb.SetAllPoints and bottomAnchor == frame and yOff == 0 then
        hb:SetAllPoints(frame)
    elseif hb.SetPoint then
        hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        hb:SetPoint("BOTTOMRIGHT", bottomAnchor, "BOTTOMRIGHT", 0, yOff)
    end

    -- Keep it above the unitframe visuals

    if hb.SetFrameStrata and frame.GetFrameStrata then
        hb:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    end
    if hb.SetFrameLevel and frame.GetFrameLevel then
        hb:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    end

    -- Safety: if the unitframe hides while hovered, also hide the highlight
    if not hb.MSUF_hideHooked and hooksecurefunc and frame.Hide then
        hb.MSUF_hideHooked = true
        hooksecurefunc(frame, "Hide", function()
            if hb and hb.Hide then
                hb:Hide()
            end
        end)
    end
end
-- Export so other files can re-fix highlight anchors (e.g. after detach state changes)
_G.MSUF_FixHighlightForFrame = MSUF_FixHighlightForFrame

function ns.MSUF_FixMouseoverHighlightBindings()
    -- Prefer EnumerateFrames() (safe, doesn't touch _G and avoids odd tables like _G itself).
    if _G.EnumerateFrames then
        local f = _G.EnumerateFrames()
        while f do
            local okName, name = MSUF_FastCall(f.GetName, f)
            if okName and type(name) == "string" and name:match("^MSUF_") then
                if MSUF_GetHighlightObject(f) then
                    MSUF_FixHighlightForFrame(f)
                end
            end
            f = _G.EnumerateFrames(f)
        end
        return
    end

    -- Fallback: scan globals, but be extremely defensive (some tables may expose GetName accidentally).
    for _, v in pairs(_G) do
        local tv = type(v)
        if v and v ~= _G and (tv == "table" or tv == "userdata") then
            if type(v.GetName) == "function" and type(v.GetObjectType) == "function" then
                local okName, name = MSUF_FastCall(v.GetName, v)
                if okName and type(name) == "string" and name:match("^MSUF_") then
                    if MSUF_GetHighlightObject(v) then
                        MSUF_FixHighlightForFrame(v)
                    end
                end
            end
        end
    end
end

-- Throttled scheduler so we don't repeatedly enumerate frames during rapid UI changes.
-- P1 perf: after one successful scan, never scan again until /reload (session-only).
do
    local scheduled = false
    function ns.MSUF_ScheduleMouseoverHighlightFix()
        if ns and ns._msufHoverFixDone then return end
        if scheduled then return end
        scheduled = true

        local function run()
            scheduled = false
            if not (ns and ns.MSUF_FixMouseoverHighlightBindings) then
                return
            end

            ns.MSUF_FixMouseoverHighlightBindings()

            -- Mark done for this session. This scan is expensive (EnumerateFrames),
            -- and should not run again from PushVisualUpdates.
            ns._msufHoverFixDone = true
        end

        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, run)
        else
            run()
        end
    end
end

-- One-time safety pass after load (covers cases where highlight existed before Colors loaded)
if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(1, function()
        if ns and ns.MSUF_ScheduleMouseoverHighlightFix then
            ns.MSUF_ScheduleMouseoverHighlightFix()
        elseif ns and ns.MSUF_FixMouseoverHighlightBindings then
            ns.MSUF_FixMouseoverHighlightBindings()
        end
    end)
end


------------------------------------------------------
-- Helpers: Global font color
------------------------------------------------------
local function GetGlobalFontColor()
    if not EnsureDB or not MSUF_DB then
        return 1, 1, 1
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    if g.useCustomFontColor
       and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB
    then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end

    return 1, 1, 1
end

local function SetGlobalFontColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.fontColorCustomR = r or 1
    general.fontColorCustomG = g or 1
    general.fontColorCustomB = b or 1
    general.useCustomFontColor = true

    PushVisualUpdates()
end

local function ResetGlobalFontToPalette()
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    g.useCustomFontColor = false
    g.fontColorCustomR = nil
    g.fontColorCustomG = nil
    g.fontColorCustomB = nil

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Castbar text color (custom RGB; falls back to Global font color)
------------------------------------------------------
local function GetCastbarTextColor()
    if not EnsureDB or not MSUF_DB then
        return GetGlobalFontColor()
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local r = tonumber(g.castbarTextR)
    local gg = tonumber(g.castbarTextG)
    local b = tonumber(g.castbarTextB)

    if r and gg and b then
        return r, gg, b
    end

    -- Fallback: global font color (custom or palette)
    return GetGlobalFontColor()
end
-- global alias for runtime (Castbars)
MSUF_GetCastbarTextColor = GetCastbarTextColor

local function SetCastbarTextColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.castbarTextR = r or 1
    general.castbarTextG = g or 1
    general.castbarTextB = b or 1
    general.castbarTextUseCustom = true

    PushVisualUpdates()
end

local function ResetCastbarTextColorToGlobal()
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    g.castbarTextR = nil
    g.castbarTextG = nil
    g.castbarTextB = nil
    g.castbarTextUseCustom = false

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Castbar border color (Outline)
------------------------------------------------------
local function GetCastbarBorderColor()
    if not EnsureDB or not MSUF_DB then
        return 0, 0, 0, 1
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local r  = tonumber(g.castbarBorderR); if r  == nil then r  = 0 end
    local gg = tonumber(g.castbarBorderG); if gg == nil then gg = 0 end
    local b  = tonumber(g.castbarBorderB); if b  == nil then b  = 0 end
    local a  = tonumber(g.castbarBorderA); if a  == nil then a  = 1 end
    return r, gg, b, a
end

local function SetCastbarBorderColor(r, g, b, a)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.castbarBorderR = r
    general.castbarBorderG = g
    general.castbarBorderB = b
    general.castbarBorderA = a or 1

    if _G.MSUF_ApplyCastbarOutlineToAll then
        _G.MSUF_ApplyCastbarOutlineToAll(true)
    end
end

local function ResetCastbarBorderColor()
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    g.castbarBorderR = nil
    g.castbarBorderG = nil
    g.castbarBorderB = nil
    g.castbarBorderA = nil

    if _G.MSUF_ApplyCastbarOutlineToAll then
        _G.MSUF_ApplyCastbarOutlineToAll(true)
    end
end


------------------------------------------------------
-- Helpers: Castbar background color
-- DB keys: MSUF_DB.general.castbarBgR/G/B/A
-- Default: 0.176, 0.176, 0.176, 1 (dark grey, matches legacy)
------------------------------------------------------
local function GetCastbarBackgroundColor()
    if not EnsureDB or not MSUF_DB then
        return 0.176, 0.176, 0.176, 1
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local r  = tonumber(g.castbarBgR)
    local gg = tonumber(g.castbarBgG)
    local b  = tonumber(g.castbarBgB)
    local a  = tonumber(g.castbarBgA)

    if r and gg and b then
        return r, gg, b, a or 1
    end

    return 0.176, 0.176, 0.176, 1
end
-- Global alias so CastbarVisuals + CastbarFrames pick it up at runtime
_G.MSUF_GetCastbarBackgroundColor = GetCastbarBackgroundColor

local function SetCastbarBackgroundColor(r, g, b, a)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.castbarBgR = r
    general.castbarBgG = g
    general.castbarBgB = b
    general.castbarBgA = a or 1

    -- Live-apply to all active castbar frames (same pattern as SetCastbarBorderColor)
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
end

local function ResetCastbarBackgroundColor()
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    g.castbarBgR = nil
    g.castbarBgG = nil
    g.castbarBgB = nil
    g.castbarBgA = nil

    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
end


------------------------------------------------------
-- Helpers: Interruptible cast color
------------------------------------------------------
local function GetInterruptibleCastColor()
    if not EnsureDB or not MSUF_DB then
        return 0, 0.9, 0.8
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    -- Neuer Weg: freie RGB-Farbe
    if g.castbarInterruptibleR and g.castbarInterruptibleG and g.castbarInterruptibleB then
        return g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB
    end

    -- Alter Weg: Palette-String aus alten SavedVariables
    if g.castbarInterruptibleColor and MSUF_FONT_COLORS and MSUF_FONT_COLORS[g.castbarInterruptibleColor] then
        local c = MSUF_FONT_COLORS[g.castbarInterruptibleColor]
        return c[1], c[2], c[3]
    end

    -- Fallback: Turquoise aus der Palette
    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["turquoise"] then
        local c = MSUF_FONT_COLORS["turquoise"]
        return c[1], c[2], c[3]
    end

    return 0, 0.9, 0.8
end
-- global alias, damit die Castbar-Logik im Main-File die Picker-Farbe nutzen kann
MSUF_GetInterruptibleCastColor = GetInterruptibleCastColor

local function SetInterruptibleCastColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.castbarInterruptibleR = r or 0
    general.castbarInterruptibleG = g or 0.9
    general.castbarInterruptibleB = b or 0.8

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Non-interruptible cast color
------------------------------------------------------
local function GetNonInterruptibleCastColor()
    if not EnsureDB or not MSUF_DB then
        -- Default: dunkles Rot
        return 0.4, 0.01, 0.01
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    -- Neuer Weg: freie RGB-Werte aus SavedVariables
    local r = tonumber(g.castbarNonInterruptibleR)
    local gg = tonumber(g.castbarNonInterruptibleG)
    local b = tonumber(g.castbarNonInterruptibleB)

    if r and gg and b then
        return r, gg, b
    end

    -- Alter Weg: Palette-String aus alten SavedVariables
    if g.castbarNonInterruptibleColor
        and MSUF_FONT_COLORS
        and MSUF_FONT_COLORS[g.castbarNonInterruptibleColor]
    then
        local c = MSUF_FONT_COLORS[g.castbarNonInterruptibleColor]
        return c[1], c[2], c[3]
    end

    -- Fallback: aus der Palette
    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["red"] then
        local c = MSUF_FONT_COLORS["red"]
        return c[1], c[2], c[3]
    end

    -- letzter Fallback: hartes Rot
    return 0.4, 0.01, 0.01
end

-- global alias die Castbar-Logik im Main-File
MSUF_GetNonInterruptibleCastColor = GetNonInterruptibleCastColor

local function SetNonInterruptibleCastColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.castbarNonInterruptibleR = r or 0.4
    general.castbarNonInterruptibleG = g or 0.01
    general.castbarNonInterruptibleB = b or 0.01

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Interrupt feedback color
------------------------------------------------------
local function GetInterruptFeedbackCastColor()
    if not EnsureDB or not MSUF_DB then
        return 0.8, 0.1, 0.1
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    -- Neuer Weg: freie RGB-Werte aus SavedVariables
    local r  = tonumber(g.castbarInterruptR)
    local gg = tonumber(g.castbarInterruptG)
    local b  = tonumber(g.castbarInterruptB)

    if r and gg and b then
        return r, gg, b
    end

    -- Alter Weg: Palette-String aus alten SavedVariables
    if g.castbarInterruptColor
        and MSUF_FONT_COLORS
        and MSUF_FONT_COLORS[g.castbarInterruptColor]
    then
        local c = MSUF_FONT_COLORS[g.castbarInterruptColor]
        return c[1], c[2], c[3]
    end

    -- Fallback: "red" aus der Palette
    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["red"] then
        local c = MSUF_FONT_COLORS["red"]
        return c[1], c[2], c[3]
    end

    -- letzter Fallback: hartes Rot
    return 0.8, 0.1, 0.1
end

local function SetInterruptFeedbackCastColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general

    general.castbarInterruptR = r or 0.8
    general.castbarInterruptG = g or 0.1
    general.castbarInterruptB = b or 0.1

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Player castbar override
------------------------------------------------------
local function GetPlayerCastbarOverrideEnabled()
    if not EnsureDB or not MSUF_DB then return false end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general
    return general.playerCastbarOverrideEnabled == true
end

local function SetPlayerCastbarOverrideEnabled(enabled)
    if not EnsureDB or not MSUF_DB then return end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.playerCastbarOverrideEnabled = (enabled == true)
    PushVisualUpdates()
end

local function GetPlayerCastbarOverrideMode()
    if not EnsureDB or not MSUF_DB then return "CLASS" end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local m = MSUF_DB.general.playerCastbarOverrideMode
    if m == "CUSTOM" or m == "CLASS" then return m end
    return "CLASS"
end

local function SetPlayerCastbarOverrideMode(mode)
    if not EnsureDB or not MSUF_DB then return end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.playerCastbarOverrideMode = (mode == "CUSTOM") and "CUSTOM" or "CLASS"
    PushVisualUpdates()
end

local function GetPlayerCastbarOverrideColor()
    if not EnsureDB or not MSUF_DB then return 1, 1, 1 end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general
    local r = tonumber(general.playerCastbarOverrideR) or 1
    local g = tonumber(general.playerCastbarOverrideG) or 1
    local b = tonumber(general.playerCastbarOverrideB) or 1
    return r, g, b
end

local function SetPlayerCastbarOverrideColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local general = MSUF_DB.general
    general.playerCastbarOverrideR = r or 1
    general.playerCastbarOverrideG = g or 1
    general.playerCastbarOverrideB = b or 1
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Class bar colors
------------------------------------------------------
local CLASS_TOKENS = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "MONK",
    "DRUID",
    "DEMONHUNTER",
    "EVOKER",
}

local function GetClassColor(token)
    if EnsureDB and MSUF_DB then
        EnsureDB()
        MSUF_DB.classColors = MSUF_DB.classColors or {}
        local t = MSUF_DB.classColors[token]
        if t and t.r and t.g and t.b then
            return t.r, t.g, t.b
        end
    end

    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then
        return c.r, c.g, c.b
    end

    return 1, 1, 1
end

local function SetClassColor(token, r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.classColors = MSUF_DB.classColors or {}
    local t = MSUF_DB.classColors[token] or {}
    t.r, t.g, t.b = r or 1, g or 1, b or 1
    MSUF_DB.classColors[token] = t

    PushVisualUpdates()
end

local function ResetAllClassColors()
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.classColors = nil

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Class Color bar background
------------------------------------------------------
local function GetClassBarBgColor()
    if not EnsureDB or not MSUF_DB then
        return 0, 0, 0
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local r  = tonumber(g.classBarBgR) or 0
    local gg = tonumber(g.classBarBgG) or 0
    local b  = tonumber(g.classBarBgB) or 0

    if r  < 0 then r  = 0 elseif r  > 1 then r  = 1 end
    if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
    if b  < 0 then b  = 0 elseif b  > 1 then b  = 1 end

    return r, gg, b
end

local function SetClassBarBgColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local gen = MSUF_DB.general

    gen.classBarBgR = r or 0
    gen.classBarBgG = g or 0
    gen.classBarBgB = b or 0

    PushVisualUpdates()
end

local function ResetClassBarBgColor()
    SetClassBarBgColor(0, 0, 0) -- default: black
end


------------------------------------------------------
-- Helpers: Bar background match HP color
------------------------------------------------------
local function GetBarBgMatchHP()
    if not EnsureDB or not MSUF_DB then return false end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    return MSUF_DB.general.barBgMatchHPColor and true or false
end

local function SetBarBgMatchHP(v)
    if not EnsureDB or not MSUF_DB then return end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.barBgMatchHPColor = v and true or false
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: NPC reaction colors
------------------------------------------------------
local function GetNPCDefaultColor(kind)
    if kind == "friendly" then
        return 0, 1, 0
    elseif kind == "neutral" then
        return 1, 1, 0
    elseif kind == "enemy" then
        return 1, 0, 0
    elseif kind == "dead" then
        return 0.4, 0.4, 0.4
    end
    return 1, 1, 1
end

local function GetNPCColor(kind)
    local defR, defG, defB = GetNPCDefaultColor(kind)

    if not EnsureDB or not MSUF_DB then
        return defR, defG, defB
    end

    EnsureDB()
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}
    local t = MSUF_DB.npcColors[kind]

    if t and t.r and t.g and t.b then
        return t.r, t.g, t.b
    end

    return defR, defG, defB
end

local function SetNPCColor(kind, r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}

    local t = MSUF_DB.npcColors[kind] or {}
    t.r = r or 1
    t.g = g or 1
    t.b = b or 1
    MSUF_DB.npcColors[kind] = t

    PushVisualUpdates()
end

local function ResetAllNPCColors()
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.npcColors = nil

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Pet frame bar color
------------------------------------------------------
local function GetPetFrameColor()
    -- Visual default (matches current behavior in "non-class" mode)
    local defR, defG, defB = 0, 1, 0

    if not EnsureDB or not MSUF_DB then
        return defR, defG, defB
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local r = g.petFrameColorR
    local gg = g.petFrameColorG
    local b = g.petFrameColorB

    if type(r) ~= "number" or type(gg) ~= "number" or type(b) ~= "number" then
        return defR, defG, defB
    end

    -- Clamp to [0,1] to avoid bad values without touching secret APIs.
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end

    return r, gg, b
end

local function SetPetFrameColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local gen = MSUF_DB.general

    gen.petFrameColorR = r
    gen.petFrameColorG = g
    gen.petFrameColorB = b

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Absorb / Heal-Absorb overlay colors
------------------------------------------------------
local function GetAbsorbOverlayColor()
    local r, g, b = 0.8, 0.9, 1.0
    if MSUF_DB and MSUF_DB.general then
        local gen = MSUF_DB.general
        local ar, ag, ab = gen.absorbBarColorR, gen.absorbBarColorG, gen.absorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            r, g, b = ar, ag, ab
        end
    end
    return r, g, b
end

local function SetAbsorbOverlayColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local gen = MSUF_DB.general

    gen.absorbBarColorR = r
    gen.absorbBarColorG = g
    gen.absorbBarColorB = b

    PushVisualUpdates()
end

local function GetHealAbsorbOverlayColor()
    local r, g, b = 1.0, 0.4, 0.4
    if MSUF_DB and MSUF_DB.general then
        local gen = MSUF_DB.general
        local ar, ag, ab = gen.healAbsorbBarColorR, gen.healAbsorbBarColorG, gen.healAbsorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            r, g, b = ar, ag, ab
        end
    end
    return r, g, b
end

local function SetHealAbsorbOverlayColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local gen = MSUF_DB.general

    gen.healAbsorbBarColorR = r
    gen.healAbsorbBarColorG = g
    gen.healAbsorbBarColorB = b

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Power bar background color
------------------------------------------------------
local function GetPowerBarBackgroundColor()
    -- Default: mirror current Bar background tint (base values, not dark-brightness scaled)
    local defR, defG, defB = 0, 0, 0

    if EnsureDB and MSUF_DB then
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        local br = tonumber(g.classBarBgR)
        local bg = tonumber(g.classBarBgG)
        local bb = tonumber(g.classBarBgB)

        if type(br) == "number" then defR = br end
        if type(bg) == "number" then defG = bg end
        if type(bb) == "number" then defB = bb end

        if defR < 0 then defR = 0 elseif defR > 1 then defR = 1 end
        if defG < 0 then defG = 0 elseif defG > 1 then defG = 1 end
        if defB < 0 then defB = 0 elseif defB > 1 then defB = 1 end

        local r = g.powerBarBgColorR
        local gg = g.powerBarBgColorG
        local b = g.powerBarBgColorB

        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            if r < 0 then r = 0 elseif r > 1 then r = 1 end
            if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
            if b < 0 then b = 0 elseif b > 1 then b = 1 end
            return r, gg, b
        end
    end

    return defR, defG, defB
end

local function SetPowerBarBackgroundColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local gen = MSUF_DB.general

    gen.powerBarBgColorR = r
    gen.powerBarBgColorG = g
    gen.powerBarBgColorB = b

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Aggro border color
------------------------------------------------------
local function GetAggroBorderColor()
    local defR, defG, defB = 1, 0.50, 0
    if EnsureDB and MSUF_DB then
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        local r = g.aggroBorderColorR
        local gg = g.aggroBorderColorG
        local b = g.aggroBorderColorB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return defR, defG, defB
end

local function SetAggroBorderColor(r, g, b)
    if not EnsureDB or not MSUF_DB then return end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local gen = MSUF_DB.general
    gen.aggroBorderColorR = r
    gen.aggroBorderColorG = g
    gen.aggroBorderColorB = b
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Power bar background match HP
------------------------------------------------------
local function GetPowerBarBackgroundMatchHP()
    if MSUF_DB and MSUF_DB.general then
        local v = MSUF_DB.general.powerBarBgMatchHPColor
        if v ~= nil then
            return v and true or false
        end
    end
    -- Legacy fallback (older patch stored this under bars)
    if MSUF_DB and MSUF_DB.bars then
        return MSUF_DB.bars.powerBarBgMatchBarColor and true or false
    end
    return false
end

local function SetPowerBarBackgroundMatchHP(enabled)
    if not EnsureDB or not MSUF_DB then return end
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.bars = MSUF_DB.bars or {}

    local v = enabled and true or false
    MSUF_DB.general.powerBarBgMatchHPColor = v
    -- Keep legacy key in sync (so older UI paths still reflect the state)
    MSUF_DB.bars.powerBarBgMatchBarColor = v

    PushVisualUpdates()
end


------------------------------------------------------
-- Export API table for MSUF_Options_Colors.lua
-- Options file aliases these back to locals at file scope,
-- so the panel builder body requires zero code changes.
------------------------------------------------------
ns._colorsAPI = {
    PushVisualUpdates               = PushVisualUpdates,

    -- Font
    GetGlobalFontColor              = GetGlobalFontColor,
    SetGlobalFontColor              = SetGlobalFontColor,
    ResetGlobalFontToPalette        = ResetGlobalFontToPalette,

    -- Castbar text
    GetCastbarTextColor             = GetCastbarTextColor,
    SetCastbarTextColor             = SetCastbarTextColor,
    ResetCastbarTextColorToGlobal   = ResetCastbarTextColorToGlobal,

    -- Castbar border
    GetCastbarBorderColor           = GetCastbarBorderColor,
    SetCastbarBorderColor           = SetCastbarBorderColor,
    ResetCastbarBorderColor         = ResetCastbarBorderColor,

    -- Castbar background
    GetCastbarBackgroundColor       = GetCastbarBackgroundColor,
    SetCastbarBackgroundColor       = SetCastbarBackgroundColor,
    ResetCastbarBackgroundColor     = ResetCastbarBackgroundColor,

    -- Interruptible / Non-interruptible / Feedback
    GetInterruptibleCastColor       = GetInterruptibleCastColor,
    SetInterruptibleCastColor       = SetInterruptibleCastColor,
    GetNonInterruptibleCastColor    = GetNonInterruptibleCastColor,
    SetNonInterruptibleCastColor    = SetNonInterruptibleCastColor,
    GetInterruptFeedbackCastColor   = GetInterruptFeedbackCastColor,
    SetInterruptFeedbackCastColor   = SetInterruptFeedbackCastColor,

    -- Player castbar override
    GetPlayerCastbarOverrideEnabled = GetPlayerCastbarOverrideEnabled,
    SetPlayerCastbarOverrideEnabled = SetPlayerCastbarOverrideEnabled,
    GetPlayerCastbarOverrideMode    = GetPlayerCastbarOverrideMode,
    SetPlayerCastbarOverrideMode    = SetPlayerCastbarOverrideMode,
    GetPlayerCastbarOverrideColor   = GetPlayerCastbarOverrideColor,
    SetPlayerCastbarOverrideColor   = SetPlayerCastbarOverrideColor,

    -- Class colors
    CLASS_TOKENS                    = CLASS_TOKENS,
    GetClassColor                   = GetClassColor,
    SetClassColor                   = SetClassColor,
    ResetAllClassColors             = ResetAllClassColors,

    -- Class bar background
    GetClassBarBgColor              = GetClassBarBgColor,
    SetClassBarBgColor              = SetClassBarBgColor,
    ResetClassBarBgColor            = ResetClassBarBgColor,

    -- Bar bg match HP
    GetBarBgMatchHP                 = GetBarBgMatchHP,
    SetBarBgMatchHP                 = SetBarBgMatchHP,

    -- NPC
    GetNPCColor                     = GetNPCColor,
    SetNPCColor                     = SetNPCColor,
    ResetAllNPCColors               = ResetAllNPCColors,

    -- Pet
    GetPetFrameColor                = GetPetFrameColor,
    SetPetFrameColor                = SetPetFrameColor,

    -- Absorb / Heal-Absorb
    GetAbsorbOverlayColor           = GetAbsorbOverlayColor,
    SetAbsorbOverlayColor           = SetAbsorbOverlayColor,
    GetHealAbsorbOverlayColor       = GetHealAbsorbOverlayColor,
    SetHealAbsorbOverlayColor       = SetHealAbsorbOverlayColor,

    -- Power bar bg
    GetPowerBarBackgroundColor      = GetPowerBarBackgroundColor,
    SetPowerBarBackgroundColor      = SetPowerBarBackgroundColor,

    -- Aggro border
    GetAggroBorderColor             = GetAggroBorderColor,
    SetAggroBorderColor             = SetAggroBorderColor,

    -- Power bar bg match HP
    GetPowerBarBackgroundMatchHP    = GetPowerBarBackgroundMatchHP,
    SetPowerBarBackgroundMatchHP    = SetPowerBarBackgroundMatchHP,
}
