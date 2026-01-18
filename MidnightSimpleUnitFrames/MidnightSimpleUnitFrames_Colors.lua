-- MidnightSimpleUnitFrames_Colors.lua
-- Options panel for color settings:
--  - Global font color
--  - Per-class bar colors
--  - Class Color bar background
--  - NPC reaction colors
--  - New colors for global settings added 

local addonName, ns = ...
ns = ns or {}

------------------------------------------------------
-- Local shortcuts
------------------------------------------------------
local CreateFrame                  = CreateFrame
local Settings                     = Settings
local ColorPickerFrame             = ColorPickerFrame
local InterfaceOptions_AddCategory = InterfaceOptions_AddCategory

local UIDropDownMenu_CreateInfo      = UIDropDownMenu_CreateInfo
local UIDropDownMenu_SetWidth       = UIDropDownMenu_SetWidth
local UIDropDownMenu_Initialize     = UIDropDownMenu_Initialize
local UIDropDownMenu_SetSelectedValue = UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_AddButton      = UIDropDownMenu_AddButton

local EnsureDB                     = _G.EnsureDB
local RAID_CLASS_COLORS            = RAID_CLASS_COLORS
local C_Timer                      = C_Timer

------------------------------------------------------
-- Helper: expand dropdown click area (Colors menu)
-- Makes the entire dropdown bar clickable, not just the arrow button.
-- We expand only to the LEFT to avoid stealing clicks from controls placed
-- to the right (e.g. color swatches / reset buttons).
------------------------------------------------------
local function MSUF_ExpandDropdownClickArea(dropdown)
    if not dropdown or dropdown._msufClickAreaExpanded then return end

    local btn = dropdown.Button
    if not btn and dropdown.GetName then
        local nm = dropdown:GetName()
        if nm then btn = _G[nm .. "Button"] end
    end
    if not btn or not btn.SetHitRectInsets then return end

    btn:SetHitRectInsets(-260, 0, -8, -8)
    dropdown._msufClickAreaExpanded = true
end


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
local hooksecurefunc = hooksecurefunc
local _G = _G

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
    local pb =
        frame.targetPowerBar or frame.TargetPowerBar or frame.powerBar or frame.PowerBar
        or frame.power or frame.Power or frame.ManaBar or frame.manaBar
        or frame.MSUF_powerBar or frame.MSUF_PowerBar or frame.MSUFPowerBar
        or frame.resourceBar or frame.ResourceBar or frame.classPowerBar or frame.ClassPowerBar

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
    if bottomAnchor == frame and frame.GetChildren then
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
do
    local scheduled = false
    function ns.MSUF_ScheduleMouseoverHighlightFix()
        if scheduled then return end
        scheduled = true

        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                scheduled = false
                if ns and ns.MSUF_FixMouseoverHighlightBindings then
                    ns.MSUF_FixMouseoverHighlightBindings()
                end
            end)
        else
            scheduled = false
            if ns and ns.MSUF_FixMouseoverHighlightBindings then
                ns.MSUF_FixMouseoverHighlightBindings()
            end
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


-- Castbar text color helpers (custom RGB picker; falls back to Global font color)
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


-- Castbar border color helpers (Outline)
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

-- Interruptible cast color helpers (for custom RGB picker)
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
-- Helpers: Non-interruptible cast color (Colorpicker + Fallbacks)
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

    -- Fallback: „red“ aus der Palette
    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["red"] then
        local c = MSUF_FONT_COLORS["red"]
        return c[1], c[2], c[3]
    end

    -- letzter Fallback: hartes Rot
    return 0.4, 0.01, 0.01
end

-- global alias für die Castbar-Logik im Main-File
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
-- Helpers: Interrupt feedback color (all castbars, Colorpicker + Fallbacks)
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

-- Player castbar color override (Variant A)
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
-- Helpers: Class Color bar background (Class Color bar mode only)
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
-- Helpers: Bar background tint can optionally match the current HP bar color
-- Stored under MSUF_DB.general.barBgMatchHPColor.
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
-- Helpers: Pet frame bar color (foreground HP bar)
-- Stored under MSUF_DB.general.petFrameColorR/G/B.
-- Nil = no override (pet follows normal bar coloring).
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
-- Helpers: Absorb / Heal-Absorb overlay colors (HP overlays)
-- Stored under MSUF_DB.general.absorbBarColorR/G/B and healAbsorbBarColorR/G/B.
-- Nil = default overlay colors.
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
-- Helpers: Power bar background color (background texture tint for power bar only)
-- Stored under MSUF_DB.general.powerBarBgColorR/G/B.
-- Nil = follow the global Bar background tint.
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


-- Toggle: Match power bar background hue to the CURRENT health bar color.
-- Stored under MSUF_DB.general.powerBarBgMatchHPColor.
-- Backward-compatible: also mirrors MSUF_DB.bars.powerBarBgMatchBarColor (legacy location).
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
-- Helper: ColorPicker wrapper
------------------------------------------------------
local function OpenColorPicker(initialR, initialG, initialB, callback)
    if not ColorPickerFrame or type(callback) ~= "function" then return end

    -- Snapshot the color as it was BEFORE opening the picker.
    -- We use this for proper Cancel behavior (revert live swatch changes).
    local startR = tonumber(initialR) or 1
    local startG = tonumber(initialG) or 1
    local startB = tonumber(initialB) or 1

    if ColorPickerFrame.SetupColorPickerAndShow then
        -- modern API
        local info = {
            r          = startR,
            g          = startG,
            b          = startB,
            opacity    = 1,
            hasOpacity = false,

            -- Called when the user changes the color (live preview).
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                callback(r, g, b)
            end,

            -- Called when the user presses Cancel.
            cancelFunc = function(previousValues)
                if type(previousValues) == "table" then
                    callback(previousValues.r or startR, previousValues.g or startG, previousValues.b or startB)
                else
                    callback(startR, startG, startB)
                end
            end,
        }

        -- Some builds use previousValues for Cancel; harmless if ignored.
        info.previousValues = { r = startR, g = startG, b = startB, opacity = 1 }

        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- fallback
        local function OnColorChanged()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            callback(r, g, b)
        end

        ColorPickerFrame.func        = OnColorChanged
        ColorPickerFrame.cancelFunc  = function(previousValues)
            if type(previousValues) == "table" then
                callback(previousValues.r or startR, previousValues.g or startG, previousValues.b or startB)
            else
                callback(startR, startG, startB)
            end
        end
        ColorPickerFrame.previousValues = { r = startR, g = startG, b = startB }

        ColorPickerFrame.hasOpacity  = false
        ColorPickerFrame:SetColorRGB(startR, startG, startB)
        ColorPickerFrame:Show()
    end
end

------------------------------------------------------
-- Public: register Colors options panel (with scrolling)
------------------------------------------------------
function ns.MSUF_RegisterColorsOptions_Full(parentCategory)
    --------------------------------------------------
    -- Root panel & scroll container
    --------------------------------------------------
    local panel = (_G and _G.MSUF_ColorsPanel) or CreateFrame("Frame", "MSUF_ColorsPanel", UIParent)
    panel.name = "Colors"

    if panel.__MSUF_ColorsBuilt then
        return panel
    end

    local scrollFrame = CreateFrame("ScrollFrame", "MSUF_ColorsScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 0)

    local content = CreateFrame("Frame", "MSUF_ColorsScrollChild", scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetWidth(640)
    content:SetHeight(600)

    scrollFrame:SetScrollChild(content)

    local fontSwatchTex
    local classBgSwatchTex
    local classBgMatchCheck
    local npcFriendlyTex
    local npcNeutralTex
    local npcEnemyTex
    local npcDeadTex
    local petFrameTex
    local interruptibleTex        -- texture for interruptible cast color swatch
    local nonInterruptibleTex     -- texture for non-interruptible cast color swatch
    local interruptFeedbackTex    -- texture for interrupt feedback color swatch
    local highlightEnableCheck
    local highlightColorTex
    local classSwatches = {}  -- token -> texture
    local classLabels   = {}  -- token -> FontString
    local lastControl   -- lowest widget for dynamic height

    -- Bar appearance controls (moved from Bars menu)
    local barModeDrop
    local darkToneSlider
    local darkToneLabelFS
    local darkToneValueText
    local barAppearanceRefreshing = false

    local UpdateDarkToneValueText
    local UpdateDarkBarControls
    local UpdateHighlightControls
    -- Func table to avoid 200-local limit (store helper funcs as fields, not locals)
    local F = panel.__MSUF_ColorsFuncs
    if not F then
        F = {}
        panel.__MSUF_ColorsFuncs = F
    end

    --------------------------------------------------
    -- Helper: section divider (like Gameplay tab)
    --------------------------------------------------
    F.CreateHeaderDividerAbove = function(header)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.15)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 0, 8)
        line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        return line
    end


--------------------------------------------------
-- Helper: toggle greyout (like main menu)
-- When a feature toggle is OFF, it should look disabled (greyed),
-- but remain clickable.
--------------------------------------------------
F.ApplyToggleGreyout = function(checkBtn, isOn)
    if not checkBtn then return end
    local on = isOn
    if on == nil and checkBtn.GetChecked then
        on = (checkBtn:GetChecked() == true)
    end
    local a = on and 1 or 0.35
    if checkBtn.SetAlpha then checkBtn:SetAlpha(a) end
    if checkBtn.text and checkBtn.text.SetAlpha then
        checkBtn.text:SetAlpha(a)
    end
end

    --------------------------------------------------
    --------------------------------------------------
-- Contrast helper for class labels
--------------------------------------------------
F.SetLabelContrast = function(label, r, g, b)
    if not label then return end
    -- Intentionally keep labels readable and consistent:
    -- Always white text with a black shadow (avoid automatic black text on bright colors).
    label:SetTextColor(1, 1, 1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
end

    --------------------------------------------------
    -- Title + description
    --------------------------------------------------
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames - Colors")

    local subText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subText:SetWidth(600)
    subText:SetJustifyH("LEFT")
    subText:SetText("Configure global colors such as the global font color, per-class bar colors, and NPC reaction colors.")

    --------------------------------------------------

    --------------------------------------------------
    -- Global font color
    --------------------------------------------------
    local fontLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -24)
    fontLabel:SetText("Global font color")
    F.CreateHeaderDividerAbove(fontLabel)

    local fontSwatch = CreateFrame("Button", "MSUF_Colors_FontSwatchButton", content)
    fontSwatch:SetSize(32, 16)
    fontSwatch:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -8)

    fontSwatchTex = fontSwatch:CreateTexture(nil, "ARTWORK")
    fontSwatchTex:SetAllPoints()

    fontSwatch:SetScript("OnClick", function()
        local r, g, b = GetGlobalFontColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetGlobalFontColor(nr, ng, nb)
            fontSwatchTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    local fontResetBtn = CreateFrame("Button", "MSUF_Colors_FontResetButton", content, "UIPanelButtonTemplate")
    fontResetBtn:SetSize(140, 22)
    fontResetBtn:SetPoint("TOPLEFT", fontSwatch, "BOTTOMLEFT", 0, -8)
    fontResetBtn:SetText("Use font palette")
    fontResetBtn:SetScript("OnClick", function()
        ResetGlobalFontToPalette()
        local r, g, b = GetGlobalFontColor()
        fontSwatchTex:SetColorTexture(r, g, b)
    end)

    --------------------------------------------------
    -- Class bar colors (5 / 5 / 3, Klassennamen auf den Bars)
    --------------------------------------------------
    local classHeader = content:CreateFontString("MSUF_Colors_ClassHeader", "ARTWORK", "GameFontNormal")
    classHeader:SetPoint("TOPLEFT", fontResetBtn, "BOTTOMLEFT", 0, -32)
    classHeader:SetText("Class bar colors")
    F.CreateHeaderDividerAbove(classHeader)

    local classSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    classSub:SetPoint("TOPLEFT", classHeader, "BOTTOMLEFT", 0, -4)
    classSub:SetWidth(600)
    classSub:SetJustifyH("LEFT")
    classSub:SetText("Choose an override bar color per class.")

    local startY    = -36
    local rowHeight = 22
    local colWidth  = 110   -- Platz pro Spalte
    local barOffset = 30    -- Abstand innerhalb der Spalte bis zum Balken

    local rowSizes   = { 5, 5, 3 }   -- 5 / 5 / 3 = 13 Klassen
    local rowCount   = #rowSizes
    local classIndex = 1

    for rowIndex, rowSize in ipairs(rowSizes) do
        for colIndex = 1, rowSize do
            local token = CLASS_TOKENS[classIndex]
            if not token then break end
            classIndex = classIndex + 1

            local lower = token:lower()
            local className
            if lower == "deathknight" then
                className = "DK"
            elseif lower == "demonhunter" then
                className = "DH"
            else
                className = lower:sub(1, 1):upper() .. lower:sub(2)
            end

            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]

            local xOffset = (colIndex - 1) * colWidth
            local yOffset = startY - (rowIndex - 1) * rowHeight

            -- Bar an fester Position je Spalte
            local rowSwatch = CreateFrame("Button", nil, content)
            rowSwatch:SetSize(80, 16)
            rowSwatch:SetPoint("TOPLEFT", classSub, "BOTTOMLEFT", xOffset + barOffset, yOffset)

            local rowTex = rowSwatch:CreateTexture(nil, "ARTWORK")
            rowTex:SetAllPoints()
            if c then
                rowTex:SetColorTexture(c.r, c.g, c.b)
            else
                rowTex:SetColorTexture(1, 1, 1)
            end

            -- Klassename direkt auf die Bar
            local label = rowSwatch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("CENTER", rowSwatch, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(className)

            local r, g, b = GetClassColor(token)
            F.SetLabelContrast(label, r, g, b)

            classSwatches[token] = rowTex
            classLabels[token]   = label

            rowSwatch:SetScript("OnClick", function()
                local cr, cg, cb = GetClassColor(token)
                OpenColorPicker(cr, cg, cb, function(nr, ng, nb)
                    SetClassColor(token, nr, ng, nb)
                    rowTex:SetColorTexture(nr, ng, nb)
                    F.SetLabelContrast(label, nr, ng, nb)
                end)
            end)
        end
    end

    local resetOffsetY = startY - rowCount * rowHeight - 16

    local resetClassBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetClassBtn:SetSize(180, 22)
    resetClassBtn:SetPoint("TOPLEFT", classSub, "BOTTOMLEFT", 0, resetOffsetY)
    resetClassBtn:SetText("Reset all class colors")
    resetClassBtn:SetScript("OnClick", function()
        ResetAllClassColors()
        for _, token in ipairs(CLASS_TOKENS) do
            local tex   = classSwatches[token]
            local label = classLabels[token]
            if tex then
                local r, g, b = GetClassColor(token)
                tex:SetColorTexture(r, g, b)
                F.SetLabelContrast(label, r, g, b)
            end
        end
    end)

    --------------------------------------------------
    -- Bar background tint (universal)
    --------------------------------------------------
    local classBgHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    classBgHeader:SetPoint("TOPLEFT", resetClassBtn, "BOTTOMLEFT", 0, -32)
    classBgHeader:SetText("Bar background tint")
    F.CreateHeaderDividerAbove(classBgHeader)

    local classBgSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    classBgSub:SetPoint("TOPLEFT", classBgHeader, "BOTTOMLEFT", 0, -4)
    classBgSub:SetWidth(600)
    classBgSub:SetJustifyH("LEFT")
    classBgSub:SetText("Tint applied to the bar background in *all* bar modes. (Dark Mode uses this tint too.)")

    local classBgSwatch = CreateFrame("Button", "MSUF_Colors_ClassBarBgSwatch", content)
    classBgSwatch:SetSize(80, 16)
    classBgSwatch:SetPoint("TOPLEFT", classBgSub, "BOTTOMLEFT", 0, -8)

    classBgSwatchTex = classBgSwatch:CreateTexture(nil, "ARTWORK")
    classBgSwatchTex:SetAllPoints()

    classBgSwatch:SetScript("OnClick", function()
        local r, g, b = GetClassBarBgColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetClassBarBgColor(nr, ng, nb)
            classBgSwatchTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    local classBgResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    classBgResetBtn:SetSize(140, 22)
    classBgResetBtn:SetPoint("TOPLEFT", classBgSwatch, "BOTTOMLEFT", 0, -8)
    classBgResetBtn:SetText("Reset to black")
    classBgResetBtn:SetScript("OnClick", function()
        ResetClassBarBgColor()
        local r, g, b = GetClassBarBgColor()
        classBgSwatchTex:SetColorTexture(r, g, b)
    end)

    -- Optional toggle: match background tint to the current HP bar color
    -- (so users don't need to pick a separate tint color)
    local classBgMatchCheck = CreateFrame("CheckButton", "MSUF_Colors_BarBgMatchHP", content, "UICheckButtonTemplate")
    classBgMatchCheck:SetPoint("LEFT", classBgSwatch, "RIGHT", 14, 0)
    if not classBgMatchCheck.text then
        classBgMatchCheck.text = classBgMatchCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        classBgMatchCheck.text:SetPoint("LEFT", classBgMatchCheck, "RIGHT", 2, 0)
    end
    classBgMatchCheck.text:SetText("Match HP")

    local function UpdateClassBgMatchState()
        local match = GetBarBgMatchHP()
        classBgMatchCheck:SetChecked(match)
        if classBgSwatch and classBgSwatch.EnableMouse then
            classBgSwatch:EnableMouse(not match)
        end
        if classBgSwatch and classBgSwatch.SetAlpha then
            classBgSwatch:SetAlpha(match and 0.5 or 1)
        end
        if classBgResetBtn and classBgResetBtn.SetEnabled then
            classBgResetBtn:SetEnabled(not match)
        end
    end

    classBgMatchCheck:SetScript("OnClick", function(btn)
        SetBarBgMatchHP(btn:GetChecked())
        UpdateClassBgMatchState()
    end)

    -- Initial state
    UpdateClassBgMatchState()


    --------------------------------------------------
    -- Bar appearance (moved from Bars menu)
    --------------------------------------------------
    local barAppHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barAppHeader:SetPoint("TOPLEFT", classBgResetBtn, "BOTTOMLEFT", 0, -28)
    barAppHeader:SetText("Bar appearance")
    F.CreateHeaderDividerAbove(barAppHeader)

    local barModeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barModeLabel:SetPoint("TOPLEFT", barAppHeader, "BOTTOMLEFT", 0, -10)
    barModeLabel:SetText("Bar mode")

    local barModeOptions = {
        { key = "dark",    label = "Dark Mode (dark black bars)" },
        { key = "class",   label = "Class Color Mode (color HP bars)" },
        { key = "unified", label = "Unified Color Mode (one color for all frames)" },
    }

    barModeDrop = CreateFrame("Frame", "MSUF_Colors_BarModeDropdown", content, "UIDropDownMenuTemplate")
    barModeDrop:SetPoint("TOPLEFT", barModeLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(barModeDrop, 240)
    MSUF_ExpandDropdownClickArea(barModeDrop)

    F.BarModeDropdown_Initialize = function(self, level)
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local current = g.barMode
        if current ~= "dark" and current ~= "class" and current ~= "unified" then
            current = (g.useClassColors and "class") or "dark"
        end

        for _, opt in ipairs(barModeOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.label
            info.value = opt.key
            info.func  = function(btn)
                if barAppearanceRefreshing then return end
                EnsureDB()
                if not MSUF_DB.general then MSUF_DB.general = {} end
                local mode = btn.value
                MSUF_DB.general.barMode = mode

                -- Keep legacy booleans in sync
                if mode == "dark" then
                    MSUF_DB.general.darkMode       = true
                    MSUF_DB.general.useClassColors = false
                elseif mode == "class" then
                    MSUF_DB.general.darkMode       = false
                    MSUF_DB.general.useClassColors = true
                else -- unified
                    MSUF_DB.general.darkMode       = false
                    MSUF_DB.general.useClassColors = false
                end

                UIDropDownMenu_SetSelectedValue(barModeDrop, mode)
                UIDropDownMenu_SetText(barModeDrop, opt.label)

                if UpdateDarkBarControls then UpdateDarkBarControls() end
                if F.UpdateUnifiedBarControls then F.UpdateUnifiedBarControls() end
                PushVisualUpdates()
            end
            info.checked = (opt.key == current)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(barModeDrop, F.BarModeDropdown_Initialize)


    -- Unified bar color (only used when Bar mode == "unified")
    local unifiedLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unifiedLabel:SetPoint("TOPLEFT", barModeDrop, "BOTTOMLEFT", 16, -18)
    unifiedLabel:SetText("Unified bar color")

    local unifiedSwatch = CreateFrame("Button", "MSUF_Colors_UnifiedBarSwatch", content)
    unifiedSwatch:SetSize(240, 16)
    unifiedSwatch:SetPoint("TOPLEFT", unifiedLabel, "BOTTOMLEFT", 0, -8)

    local unifiedTex = unifiedSwatch:CreateTexture(nil, "ARTWORK")
    unifiedTex:SetAllPoints()

    local unifiedResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    unifiedResetBtn:SetSize(140, 22)
    unifiedResetBtn:SetPoint("TOPLEFT", unifiedSwatch, "BOTTOMLEFT", 0, -8)
    unifiedResetBtn:SetText("Reset to default")

    local function MSUF_GetUnifiedBarColor()
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local r, gg, b = g.unifiedBarR, g.unifiedBarG, g.unifiedBarB
        if type(r) ~= "number" or type(gg) ~= "number" or type(b) ~= "number" then
            -- Reasonable default (slightly desaturated cyan)
            r, gg, b = 0.10, 0.60, 0.90
        end
        if r < 0 then r = 0 elseif r > 1 then r = 1 end
        if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
        if b < 0 then b = 0 elseif b > 1 then b = 1 end
        return r, gg, b
    end

    local function MSUF_SetUnifiedBarColor(r, gg, b)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.unifiedBarR = r
        MSUF_DB.general.unifiedBarG = gg
        MSUF_DB.general.unifiedBarB = b
    end

    local function MSUF_ResetUnifiedBarColor()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.unifiedBarR = 0.10
        MSUF_DB.general.unifiedBarG = 0.60
        MSUF_DB.general.unifiedBarB = 0.90
    end

    unifiedSwatch:SetScript("OnClick", function()
        local r, gg, b = MSUF_GetUnifiedBarColor()
        OpenColorPicker(r, gg, b, function(nr, ng, nb)
            MSUF_SetUnifiedBarColor(nr, ng, nb)
            unifiedTex:SetColorTexture(nr, ng, nb)
            PushVisualUpdates()
        end)
    end)

    unifiedResetBtn:SetScript("OnClick", function()
        MSUF_ResetUnifiedBarColor()
        local r, gg, b = MSUF_GetUnifiedBarColor()
        unifiedTex:SetColorTexture(r, gg, b)
        PushVisualUpdates()
    end)

    local function UpdateUnifiedBarControls()
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
            mode = (g.useClassColors and "class") or "dark"
        end
        local enabled = (mode == "unified")
        local a = enabled and 1 or 0.35

        unifiedLabel:SetAlpha(a)
        unifiedSwatch:SetAlpha(a)
        unifiedResetBtn:SetAlpha(a)
        unifiedSwatch:EnableMouse(enabled and true or false)
        unifiedResetBtn:SetEnabled(enabled and true or false)
    end

    -- Init swatch + state
    do
        local r, gg, b = MSUF_GetUnifiedBarColor()
        unifiedTex:SetColorTexture(r, gg, b)
        UpdateUnifiedBarControls()
        -- Expose updater so dropdown selection can refresh both sets
        F.UpdateUnifiedBarControls = UpdateUnifiedBarControls
    end
local darkToneLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
darkToneLabel:SetPoint("TOPLEFT", unifiedResetBtn, "BOTTOMLEFT", 0, -18)
darkToneLabel:SetText("Dark mode bar color")

    darkToneLabelFS = darkToneLabel

-- Continuous gray "picker" bar (ColorPicker-style, but HORIZONTAL)
-- NOTE: We intentionally implement this as a plain Frame (NOT a Slider).
-- Some Midnight/Beta builds / skin passes can reskin Slider widgets into the vertical "eye" slider.
-- A plain Frame with our own drag logic is stable and guarantees the requested horizontal behavior.

-- Hide any legacy widget that might still exist from older builds (defensive; no errors if nil)
do
    local legacy = _G["MSUF_Colors_DarkToneSlider"]
    if legacy and legacy.Hide and legacy ~= darkToneSlider then
        legacy:Hide()
    end
end

darkToneSlider = CreateFrame("Frame", "MSUF_Colors_DarkToneSlider", content)
darkToneSlider:SetSize(240, 14)
darkToneSlider:SetPoint("TOPLEFT", darkToneLabel, "BOTTOMLEFT", 0, -10)
darkToneSlider:EnableMouse(true)

local darkToneBG = darkToneSlider:CreateTexture(nil, "BACKGROUND")
darkToneBG:SetAllPoints()
darkToneBG:SetColorTexture(1, 1, 1, 1)

-- black (left) -> white (right)  (so moving toward white makes the bar LIGHTER)
do
    local ok = false
    if darkToneBG.SetGradientAlpha then
        ok = pcall(function()
            darkToneBG:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 1,  1, 1, 1, 1)
        end)
    elseif darkToneBG.SetGradient and CreateColor then
        ok = pcall(function()
            darkToneBG:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 1), CreateColor(1, 1, 1, 1))
        end)
    end
    if not ok then
        -- fallback: readable neutral background (no crash)
        darkToneBG:SetColorTexture(0.65, 0.65, 0.65, 1)
    end
end

-- Border (subtle)
if darkToneSlider.SetBackdrop then
    darkToneSlider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    darkToneSlider:SetBackdropColor(0, 0, 0, 0)
    darkToneSlider:SetBackdropBorderColor(0, 0, 0, 0.55)
end

local knob = darkToneSlider:CreateTexture(nil, "OVERLAY")
knob:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
knob:SetSize(16, 16)

F.ClampPct = function(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    return math.floor(v + 0.5)
end

F.PositionKnob = function(pct)
    if not knob then return end
    local w = darkToneSlider:GetWidth() or 1
    local x = (pct / 100) * w
    knob:ClearAllPoints()
    knob:SetPoint("CENTER", darkToneSlider, "LEFT", x, 0)
end

-- Provide a minimal "Slider-like" API for existing refresh/disable logic
function darkToneSlider:SetValue(pct)
    pct = F.ClampPct(pct)
    F.PositionKnob(pct)
end
function darkToneSlider:SetEnabled(enabled)
    self:EnableMouse(enabled and true or false)
end

darkToneValueText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
darkToneValueText:SetPoint("LEFT", darkToneSlider, "RIGHT", 10, 0)
darkToneValueText:SetText("0%  (#000000)")

UpdateDarkToneValueText = function(pct)
    local v = (pct or 0) / 100
    local c = math.floor(v * 255 + 0.5)
    if c < 0 then c = 0 end
    if c > 255 then c = 255 end
    if darkToneValueText then
        darkToneValueText:SetText(string.format("%d%%  (#%02X%02X%02X)", pct or 0, c, c, c))
    end
end

local _lastAppliedPct = -1
F.ApplyPct = function(pct, fromUser)
    pct = F.ClampPct(pct)

    -- Always keep the knob + label in sync, even if we early-return.
    F.PositionKnob(pct)
    if UpdateDarkToneValueText then UpdateDarkToneValueText(pct) end

    if pct == _lastAppliedPct then
        return
    end
    _lastAppliedPct = pct

    if fromUser then
        if barAppearanceRefreshing then return end
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        -- 0 = black, 1 = white
        MSUF_DB.general.darkBarGray = pct / 100
        MSUF_DB.general.darkBarTone = nil
        PushVisualUpdates()
    end
end

F.GetPctFromCursor = function()
    local cx = (GetCursorPosition())
    local scale = darkToneSlider:GetEffectiveScale() or 1
    cx = cx / scale
    local left = darkToneSlider:GetLeft() or 0
    local w = darkToneSlider:GetWidth() or 1
    return ((cx - left) / w) * 100
end

F.StopDrag = function(self)
    self.__msufDragging = nil
    self:SetScript("OnUpdate", nil)
end

darkToneSlider:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.__msufDragging = true
    F.ApplyPct(F.GetPctFromCursor(), true)
    self:SetScript("OnUpdate", function()
        if not self.__msufDragging then return end
        F.ApplyPct(F.GetPctFromCursor(), true)
    end)
end)
darkToneSlider:SetScript("OnMouseUp", F.StopDrag)
darkToneSlider:SetScript("OnHide", F.StopDrag)


-- Enable/disable dark-mode-only controls when bar mode is not "dark"
UpdateDarkBarControls = function()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local mode = g.barMode
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
        mode = (g.useClassColors and "class") or "dark"
    end
    local enabled = (mode == "dark")

    local a = enabled and 1 or 0.35

    if darkToneLabelFS then darkToneLabelFS:SetAlpha(a) end
    if darkToneSlider then
        if darkToneSlider.SetEnabled then darkToneSlider:SetEnabled(enabled) end
        darkToneSlider:SetAlpha(a)
    end
    if darkToneValueText then darkToneValueText:SetAlpha(a) end
end

if UpdateDarkBarControls then
    UpdateDarkBarControls()
end

    --------------------------------------------------
    -- Extra Color Options (Text links, Bars in Spalte rechts)
    --------------------------------------------------
    local npcHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    npcHeader:SetPoint("TOPLEFT", darkToneSlider, "BOTTOMLEFT", 0, -48)
    npcHeader:SetText("Extra Color Options")
    F.CreateHeaderDividerAbove(npcHeader)

    local npcRowHeight  = 22
    local npcStartY     = -8
    local npcLabelX     = 0    -- Text-Start
    local npcBarX       = 220  -- X-Position aller Bars
    local npcBarWidth   = 120  -- einheitliche Balkenlänge

    -- Friendly
    local friendlyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    friendlyLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY)
    friendlyLabel:SetJustifyH("LEFT")
    friendlyLabel:SetText("Friendly NPC Color")

    local npcFriendlySwatch = CreateFrame("Button", "MSUF_Colors_NPCFriendlySwatch", content)
    npcFriendlySwatch:SetSize(npcBarWidth, 16)
    npcFriendlySwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY)

    npcFriendlyTex = npcFriendlySwatch:CreateTexture(nil, "ARTWORK")
    npcFriendlyTex:SetAllPoints()

    npcFriendlySwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("friendly")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("friendly", nr, ng, nb)
            npcFriendlyTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Neutral
    local neutralLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    neutralLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - npcRowHeight)
    neutralLabel:SetJustifyH("LEFT")
    neutralLabel:SetText("Neutral NPC Color")

    local npcNeutralSwatch = CreateFrame("Button", "MSUF_Colors_NPCNeutralSwatch", content)
    npcNeutralSwatch:SetSize(npcBarWidth, 16)
    npcNeutralSwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - npcRowHeight)

    npcNeutralTex = npcNeutralSwatch:CreateTexture(nil, "ARTWORK")
    npcNeutralTex:SetAllPoints()

    npcNeutralSwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("neutral")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("neutral", nr, ng, nb)
            npcNeutralTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Enemy
    local enemyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    enemyLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - 2 * npcRowHeight)
    enemyLabel:SetJustifyH("LEFT")
    enemyLabel:SetText("Enemy NPC Color")

    local npcEnemySwatch = CreateFrame("Button", "MSUF_Colors_NPCEnemySwatch", content)
    npcEnemySwatch:SetSize(npcBarWidth, 16)
    npcEnemySwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - 2 * npcRowHeight)

    npcEnemyTex = npcEnemySwatch:CreateTexture(nil, "ARTWORK")
    npcEnemyTex:SetAllPoints()

    npcEnemySwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("enemy")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("enemy", nr, ng, nb)
            npcEnemyTex:SetColorTexture(nr, ng, nb)
        end)
    end)


    -- Dead
    local deadLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    deadLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - 3 * npcRowHeight)
    deadLabel:SetJustifyH("LEFT")
    deadLabel:SetText("Dead NPC Color")

    local npcDeadSwatch = CreateFrame("Button", "MSUF_Colors_NPCDeadSwatch", content)
    npcDeadSwatch:SetSize(npcBarWidth, 16)
    npcDeadSwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - 3 * npcRowHeight)

    npcDeadTex = npcDeadSwatch:CreateTexture(nil, "ARTWORK")
    npcDeadTex:SetAllPoints()

    npcDeadSwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("dead")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("dead", nr, ng, nb)
            npcDeadTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Pet frame
    local petLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    petLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - 4 * npcRowHeight)
    petLabel:SetJustifyH("LEFT")
    petLabel:SetText("Pet Frame Color")

    local petFrameSwatch = CreateFrame("Button", "MSUF_Colors_PetFrameSwatch", content)
    petFrameSwatch:SetSize(npcBarWidth, 16)
    petFrameSwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - 4 * npcRowHeight)

    petFrameTex = petFrameSwatch:CreateTexture(nil, "ARTWORK")
    petFrameTex:SetAllPoints()
    do
        local pr, pg, pb = GetPetFrameColor()
        petFrameTex:SetColorTexture(pr, pg, pb)
    end

    petFrameSwatch:SetScript("OnClick", function()
        local r, g, b = GetPetFrameColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPetFrameColor(nr, ng, nb)
            if petFrameTex then
                petFrameTex:SetColorTexture(nr, ng, nb)
            end
        end)
    end)


    -- Absorb overlay
    petLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    petLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - 5 * npcRowHeight)
    petLabel:SetJustifyH("LEFT")
    petLabel:SetText("Absorb Bar Color")

    petFrameSwatch = CreateFrame("Button", "MSUF_Colors_AbsorbOverlaySwatch", content)
    petFrameSwatch:SetSize(npcBarWidth, 16)
    petFrameSwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - 5 * npcRowHeight)

    panel.__MSUF_ExtraColorAbsorbTex = petFrameSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorAbsorbTex:SetAllPoints()
    panel.__MSUF_ExtraColorAbsorbTex:SetColorTexture(GetAbsorbOverlayColor())

    petFrameSwatch:SetScript("OnClick", function()
        local r, g, b = GetAbsorbOverlayColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetAbsorbOverlayColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorAbsorbTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    -- Heal-Absorb overlay
    petLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    petLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - 6 * npcRowHeight)
    petLabel:SetJustifyH("LEFT")
    petLabel:SetText("Heal-Absorb Bar Color")

    petFrameSwatch = CreateFrame("Button", "MSUF_Colors_HealAbsorbOverlaySwatch", content)
    petFrameSwatch:SetSize(npcBarWidth, 16)
    petFrameSwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - 6 * npcRowHeight)

    panel.__MSUF_ExtraColorHealAbsorbTex = petFrameSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorHealAbsorbTex:SetAllPoints()
    panel.__MSUF_ExtraColorHealAbsorbTex:SetColorTexture(GetHealAbsorbOverlayColor())

    petFrameSwatch:SetScript("OnClick", function()
        local r, g, b = GetHealAbsorbOverlayColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetHealAbsorbOverlayColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorHealAbsorbTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)


    -- Power bar background
    petLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    petLabel:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcLabelX, npcStartY - 7 * npcRowHeight)
    petLabel:SetJustifyH("LEFT")
    petLabel:SetText("Power Bar Background Color")

    petFrameSwatch = CreateFrame("Button", "MSUF_Colors_PowerBarBackgroundSwatch", content)

    panel.__MSUF_ExtraColorPowerBgSwatch = petFrameSwatch
    petFrameSwatch:SetSize(npcBarWidth, 16)
    petFrameSwatch:SetPoint("TOPLEFT", npcHeader, "BOTTOMLEFT", npcBarX, npcStartY - 7 * npcRowHeight)

    panel.__MSUF_ExtraColorPowerBgTex = petFrameSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorPowerBgTex:SetAllPoints()
    panel.__MSUF_ExtraColorPowerBgTex:SetColorTexture(GetPowerBarBackgroundColor())

    petFrameSwatch:SetScript("OnClick", function()
        local r, g, b = GetPowerBarBackgroundColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPowerBarBackgroundColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorPowerBgTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    -- Optional: dynamically match the Power BG hue to the CURRENT HP bar color
    -- (useful when the power bar is embedded into the health bar).
    panel.__MSUF_ExtraColorPowerBgMatchCheck = panel.__MSUF_ExtraColorPowerBgMatchCheck or CreateFrame("CheckButton", "MSUF_Colors_PowerBarBgMatchHP", content, "UICheckButtonTemplate")
    panel.__MSUF_ExtraColorPowerBgMatchCheck:ClearAllPoints()
    panel.__MSUF_ExtraColorPowerBgMatchCheck:SetPoint("LEFT", petFrameSwatch, "RIGHT", 14, 0)
    if not panel.__MSUF_ExtraColorPowerBgMatchCheck.text then
        panel.__MSUF_ExtraColorPowerBgMatchCheck.text = panel.__MSUF_ExtraColorPowerBgMatchCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        panel.__MSUF_ExtraColorPowerBgMatchCheck.text:SetPoint("LEFT", panel.__MSUF_ExtraColorPowerBgMatchCheck, "RIGHT", 2, 0)
    end
    panel.__MSUF_ExtraColorPowerBgMatchCheck.text:SetText("Match HP")
    panel.__MSUF_ExtraColorPowerBgMatchCheck:SetChecked(GetPowerBarBackgroundMatchHP())
    panel.__MSUF_ExtraColorPowerBgMatchCheck:SetScript("OnClick", function(btn)
        SetPowerBarBackgroundMatchHP(btn:GetChecked())
        if petFrameSwatch and petFrameSwatch.EnableMouse then
            petFrameSwatch:EnableMouse(not btn:GetChecked())
        end
        if petFrameSwatch and petFrameSwatch.SetAlpha then
            petFrameSwatch:SetAlpha(btn:GetChecked() and 0.35 or 1)
        end
    end)

    -- Initial state sync (disable the swatch when Match HP is on)
    if GetPowerBarBackgroundMatchHP() then
        if petFrameSwatch and petFrameSwatch.EnableMouse then
            petFrameSwatch:EnableMouse(false)
        end
        if petFrameSwatch and petFrameSwatch.SetAlpha then
            petFrameSwatch:SetAlpha(0.35)
        end
    else
        if petFrameSwatch and petFrameSwatch.EnableMouse then
            petFrameSwatch:EnableMouse(true)
        end
        if petFrameSwatch and petFrameSwatch.SetAlpha then
            petFrameSwatch:SetAlpha(1)
        end
    end



    -- Reset Extra Color
    local npcResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    npcResetBtn:SetSize(160, 22)
    npcResetBtn:SetPoint("TOPLEFT", petLabel, "BOTTOMLEFT", 0, -12)
    npcResetBtn:SetText("Reset Extra Color")
    npcResetBtn:SetScript("OnClick", function()
        if EnsureDB and MSUF_DB then
            EnsureDB()
            MSUF_DB.npcColors = nil

            MSUF_DB.general = MSUF_DB.general or {}
            local gen = MSUF_DB.general
            gen.absorbBarColorR, gen.absorbBarColorG, gen.absorbBarColorB = nil, nil, nil
            gen.healAbsorbBarColorR, gen.healAbsorbBarColorG, gen.healAbsorbBarColorB = nil, nil, nil
            gen.powerBarBgColorR, gen.powerBarBgColorG, gen.powerBarBgColorB = nil, nil, nil
            gen.powerBarBgMatchHPColor = nil
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.powerBarBgMatchBarColor = nil


            PushVisualUpdates()
        end

        if npcFriendlyTex then
            local fr, fg, fb = GetNPCColor("friendly")
            npcFriendlyTex:SetColorTexture(fr, fg, fb)
        end
        if npcNeutralTex then
            local nr, ng, nb = GetNPCColor("neutral")
            npcNeutralTex:SetColorTexture(nr, ng, nb)
        end
        if npcEnemyTex then
            local er, eg, eb = GetNPCColor("enemy")
            npcEnemyTex:SetColorTexture(er, eg, eb)
        end
        if npcDeadTex then
            local dr, dg, db = GetNPCColor("dead")
            npcDeadTex:SetColorTexture(dr, dg, db)
        end
        local aTex = panel.__MSUF_ExtraColorAbsorbTex
        if aTex then
            aTex:SetColorTexture(GetAbsorbOverlayColor())
        end
        local hTex = panel.__MSUF_ExtraColorHealAbsorbTex
        if hTex then
            hTex:SetColorTexture(GetHealAbsorbOverlayColor())
        end
        local pTex = panel.__MSUF_ExtraColorPowerBgTex
        if pTex then
            pTex:SetColorTexture(GetPowerBarBackgroundColor())
        end

        if panel.__MSUF_ExtraColorPowerBgMatchCheck then
            panel.__MSUF_ExtraColorPowerBgMatchCheck:SetChecked(false)
        end
        if panel.__MSUF_ExtraColorPowerBgSwatch and panel.__MSUF_ExtraColorPowerBgSwatch.EnableMouse then
            panel.__MSUF_ExtraColorPowerBgSwatch:EnableMouse(true)
        end
        if panel.__MSUF_ExtraColorPowerBgSwatch and panel.__MSUF_ExtraColorPowerBgSwatch.SetAlpha then
            panel.__MSUF_ExtraColorPowerBgSwatch:SetAlpha(1)
        end
    end)

    lastControl = npcResetBtn

    --------------------------------------------------
    -- Castbar colors
    --------------------------------------------------
    local castbarHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarHeader:SetPoint("TOPLEFT", npcResetBtn, "BOTTOMLEFT", 0, -32)
    castbarHeader:SetText("Castbar colors")
    F.CreateHeaderDividerAbove(castbarHeader)

    local castbarSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarSub:SetPoint("TOPLEFT", castbarHeader, "BOTTOMLEFT", 0, -4)
    castbarSub:SetWidth(600)
    castbarSub:SetJustifyH("LEFT")
    castbarSub:SetText("Configure colors for interruptible, non-interruptible and interrupt feedback castbars.")

    --------------------------------------------------
    -- Castbar dropdowns
    --------------------------------------------------
    -- Interruptible cast color (custom Color Picker)
    local interruptibleColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    interruptibleColorLabel:SetPoint("TOPLEFT", castbarSub, "BOTTOMLEFT", 0, -12)
    interruptibleColorLabel:SetText("Interruptible cast color")

    local interruptibleSwatch = CreateFrame("Button", "MSUF_Colors_InterruptibleCastColorSwatch", content)
    interruptibleSwatch:SetSize(32, 16)
    interruptibleSwatch:SetPoint("TOPLEFT", interruptibleColorLabel, "BOTTOMLEFT", 0, -8)

    interruptibleTex = interruptibleSwatch:CreateTexture(nil, "ARTWORK")
    interruptibleTex:SetAllPoints()

    interruptibleSwatch:SetScript("OnClick", function()
        local r, g, b = GetInterruptibleCastColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetInterruptibleCastColor(nr, ng, nb)
            interruptibleTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetInterruptibleCastColor()
        interruptibleTex:SetColorTexture(r, g, b)
    end

    local nonInterruptibleColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    nonInterruptibleColorLabel:SetPoint("TOPLEFT", interruptibleColorLabel, "BOTTOMLEFT", 0, -32)
    nonInterruptibleColorLabel:SetText("Non-interruptible cast color")

    local nonInterruptibleSwatch = CreateFrame("Button", "MSUF_Colors_NonInterruptibleCastColorSwatch", content)
    nonInterruptibleSwatch:SetSize(32, 16)
    nonInterruptibleSwatch:SetPoint("TOPLEFT", nonInterruptibleColorLabel, "BOTTOMLEFT", 0, -8)

    nonInterruptibleTex = nonInterruptibleSwatch:CreateTexture(nil, "ARTWORK")
    nonInterruptibleTex:SetAllPoints()

    nonInterruptibleSwatch:SetScript("OnClick", function()
        local r, g, b = GetNonInterruptibleCastColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNonInterruptibleCastColor(nr, ng, nb)
            nonInterruptibleTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetNonInterruptibleCastColor()
        nonInterruptibleTex:SetColorTexture(r, g, b)
    end

-- Interrupt color (all castbars)
    local interruptFeedbackColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    interruptFeedbackColorLabel:SetPoint("TOPLEFT", nonInterruptibleColorLabel, "BOTTOMLEFT", 0, -32)
    interruptFeedbackColorLabel:SetText("Interrupt color (all castbars)")

    local interruptFeedbackSwatch = CreateFrame("Button", "MSUF_Colors_InterruptFeedbackColorSwatch", content)
    interruptFeedbackSwatch:SetSize(32, 16)
    interruptFeedbackSwatch:SetPoint("TOPLEFT", interruptFeedbackColorLabel, "BOTTOMLEFT", 0, -8)

    interruptFeedbackTex = interruptFeedbackSwatch:CreateTexture(nil, "ARTWORK")
    interruptFeedbackTex:SetAllPoints()

    interruptFeedbackSwatch:SetScript("OnClick", function()
        local r, g, b = GetInterruptFeedbackCastColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetInterruptFeedbackCastColor(nr, ng, nb)
            interruptFeedbackTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetInterruptFeedbackCastColor()
        interruptFeedbackTex:SetColorTexture(r, g, b)
    end

    -- Castbar text color (custom RGB; right-click to reset to Global font color)
    local castbarTextColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTextColorLabel:SetPoint("TOPLEFT", castbarSub, "BOTTOMLEFT", 360, -12)
    castbarTextColorLabel:SetText("Castbar text color")

    local castbarTextSwatch = CreateFrame("Button", "MSUF_Colors_CastbarTextColorSwatch", content)
    castbarTextSwatch:SetSize(32, 16)
    castbarTextSwatch:SetPoint("TOPLEFT", castbarTextColorLabel, "BOTTOMLEFT", 0, -8)

    local castbarTextTex = castbarTextSwatch:CreateTexture(nil, "ARTWORK")
    castbarTextTex:SetAllPoints()

    castbarTextSwatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    castbarTextSwatch:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            ResetCastbarTextColorToGlobal()
            local rr, gg, bb = GetCastbarTextColor()
            castbarTextTex:SetColorTexture(rr, gg, bb)
            return
        end

        local r, g, b = GetCastbarTextColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetCastbarTextColor(nr, ng, nb)
            castbarTextTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetCastbarTextColor()
        castbarTextTex:SetColorTexture(r, g, b)
    end


-- Castbar border color (Outline; right-click to reset)
local castbarBorderColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
castbarBorderColorLabel:SetPoint("TOPLEFT", castbarTextSwatch, "BOTTOMLEFT", 0, -18)
castbarBorderColorLabel:SetText("Castbar border color")

local castbarBorderSwatch = CreateFrame("Button", "MSUF_Colors_CastbarBorderColorSwatch", content)
castbarBorderSwatch:SetSize(32, 16)
castbarBorderSwatch:SetPoint("TOPLEFT", castbarBorderColorLabel, "BOTTOMLEFT", 0, -8)

local castbarBorderTex = castbarBorderSwatch:CreateTexture(nil, "ARTWORK")
castbarBorderTex:SetAllPoints()

castbarBorderSwatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
castbarBorderSwatch:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
        ResetCastbarBorderColor()
        local rr, gg, bb = GetCastbarBorderColor()
        castbarBorderTex:SetColorTexture(rr, gg, bb)
        return
    end

    local r, g, b = GetCastbarBorderColor()
    OpenColorPicker(r, g, b, function(nr, ng, nb)
        SetCastbarBorderColor(nr, ng, nb, 1)
        castbarBorderTex:SetColorTexture(nr, ng, nb)
    end)
end)

do
    local r, g, b = GetCastbarBorderColor()
    castbarBorderTex:SetColorTexture(r, g, b)
end



    --------------------------------------------------
    -- Player castbar override (normal casts/channels)
    --------------------------------------------------
    local playerOverrideHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    playerOverrideHeader:SetPoint("TOPLEFT", interruptFeedbackSwatch, "BOTTOMLEFT", 0, -26)
    playerOverrideHeader:SetText("Player castbar override")

    local playerOverrideSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    playerOverrideSub:SetPoint("TOPLEFT", playerOverrideHeader, "BOTTOMLEFT", 0, -4)
    playerOverrideSub:SetWidth(600)
    playerOverrideSub:SetJustifyH("LEFT")
    playerOverrideSub:SetText("Optional: forces the Player castbar to use Class or Custom color during normal casts. Interrupt feedback still uses 'Interrupt color (all castbars)'.")

    local playerOverrideEnable = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    playerOverrideEnable:SetPoint("TOPLEFT", playerOverrideSub, "BOTTOMLEFT", 0, -10)
    playerOverrideEnable.text:SetText("Enable Player override")

    local modeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modeLabel:SetPoint("TOPLEFT", playerOverrideEnable, "BOTTOMLEFT", 0, -10)
    modeLabel:SetText("Mode:")

    local classModeCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    classModeCheck:SetPoint("LEFT", modeLabel, "RIGHT", 12, 0)
    classModeCheck.text:SetText("Class color")

    local customModeCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    customModeCheck:SetPoint("LEFT", classModeCheck, "RIGHT", 70, 0)
    customModeCheck.text:SetText("Custom color")

    local customColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    customColorLabel:SetPoint("LEFT", customModeCheck.text, "RIGHT", 18, 0)
    customColorLabel:SetText("Color:")

    local playerOverrideSwatch = CreateFrame("Button", "MSUF_Colors_PlayerCastbarOverrideSwatch", content)
    playerOverrideSwatch:SetSize(32, 16)
    playerOverrideSwatch:SetPoint("LEFT", customColorLabel, "RIGHT", 8, -1)

    local playerOverrideTex = playerOverrideSwatch:CreateTexture(nil, "ARTWORK")
    playerOverrideTex:SetAllPoints()

    F.UpdatePlayerOverrideControls = function()
        local enabled = GetPlayerCastbarOverrideEnabled()
        local mode = GetPlayerCastbarOverrideMode()

        playerOverrideEnable:SetChecked(enabled)
        F.ApplyToggleGreyout(playerOverrideEnable, enabled)

        classModeCheck:SetChecked(mode == "CLASS")
        customModeCheck:SetChecked(mode == "CUSTOM")

        -- Grey-out OFF state (like main menu): unchecked choice looks disabled but is still clickable.
        if enabled then
            F.ApplyToggleGreyout(classModeCheck, mode == "CLASS")
            F.ApplyToggleGreyout(customModeCheck, mode == "CUSTOM")
        else
            F.ApplyToggleGreyout(classModeCheck, false)
            F.ApplyToggleGreyout(customModeCheck, false)
        end

        if modeLabel then modeLabel:SetAlpha(enabled and 1 or 0.35) end

        classModeCheck:SetEnabled(enabled)
        customModeCheck:SetEnabled(enabled)

        local showCustom = enabled and (mode == "CUSTOM")
        customColorLabel:SetAlpha(showCustom and 1 or 0.35)
        playerOverrideSwatch:SetAlpha(showCustom and 1 or 0.35)
        playerOverrideSwatch:EnableMouse(showCustom)

        local r, g, b = GetPlayerCastbarOverrideColor()
        playerOverrideTex:SetColorTexture(r, g, b)
    end

    playerOverrideEnable:SetScript("OnClick", function(self)
        SetPlayerCastbarOverrideEnabled(self:GetChecked() == true)
        F.UpdatePlayerOverrideControls()
    end)

    classModeCheck:SetScript("OnClick", function()
        if not GetPlayerCastbarOverrideEnabled() then return end
        SetPlayerCastbarOverrideMode("CLASS")
        F.UpdatePlayerOverrideControls()
    end)

    customModeCheck:SetScript("OnClick", function()
        if not GetPlayerCastbarOverrideEnabled() then return end
        SetPlayerCastbarOverrideMode("CUSTOM")
        F.UpdatePlayerOverrideControls()
    end)

    playerOverrideSwatch:SetScript("OnClick", function()
        if not (GetPlayerCastbarOverrideEnabled() and GetPlayerCastbarOverrideMode() == "CUSTOM") then return end
        local r, g, b = GetPlayerCastbarOverrideColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPlayerCastbarOverrideColor(nr, ng, nb)
            playerOverrideTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    F.UpdatePlayerOverrideControls()

    local playerOverrideAnchor = playerOverrideSwatch

    -- Reset button for castbar colors
    local resetCastbarColorsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetCastbarColorsBtn:SetSize(160, 22)
    resetCastbarColorsBtn:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -10)
    resetCastbarColorsBtn:SetText("Reset castbar colors")

    resetCastbarColorsBtn:SetScript("OnClick", function()
        EnsureDB()
        local g = MSUF_DB and MSUF_DB.general
        if not g then return end

        -- Interruptible defaults
        g.castbarInterruptibleR = nil
        g.castbarInterruptibleG = nil
        g.castbarInterruptibleB = nil
        g.castbarInterruptibleColor = "turquoise"

        -- Non-interruptible defaults
        g.castbarNonInterruptibleR = nil
        g.castbarNonInterruptibleG = nil
        g.castbarNonInterruptibleB = nil
        g.castbarNonInterruptibleColor = "red"

        -- Interrupt feedback defaults
        g.castbarInterruptR = nil
        g.castbarInterruptG = nil
        g.castbarInterruptB = nil
        g.castbarInterruptColor = "red"

        -- Player override defaults
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        g.playerCastbarOverrideR = 1
        g.playerCastbarOverrideG = 1
        g.playerCastbarOverrideB = 1

        -- Update swatches in the Colors panel
        if interruptibleTex then
            local r1, g1, b1 = GetInterruptibleCastColor()
            interruptibleTex:SetColorTexture(r1, g1, b1)
        end
        if nonInterruptibleTex then
            local r2, g2, b2 = GetNonInterruptibleCastColor()
            nonInterruptibleTex:SetColorTexture(r2, g2, b2)
        end
        if interruptFeedbackTex then
            local r3, g3, b3 = GetInterruptFeedbackCastColor()
            interruptFeedbackTex:SetColorTexture(r3, g3, b3)
        end

        if F.UpdatePlayerOverrideControls then
            F.UpdatePlayerOverrideControls()
        end

        -- Update override swatch + toggles
        if playerOverrideTex then
            local r4, g4, b4 = GetPlayerCastbarOverrideColor()
            playerOverrideTex:SetColorTexture(r4, g4, b4)
        end
        if F.UpdatePlayerOverrideControls then
            F.UpdatePlayerOverrideControls()
        end

        -- Push visuals to active castbars if the helper exists
        if ns.MSUF_UpdateCastbarVisuals then
            ns.MSUF_UpdateCastbarVisuals()
        end

        if PushVisualUpdates then
            PushVisualUpdates()
        end
    end)

    lastControl = resetCastbarColorsBtn
    

    --------------------------------------------------
    -- Mouseover highlight
    --------------------------------------------------
    local mouseoverHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    mouseoverHeader:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -64)
    mouseoverHeader:SetText("Mouseover highlight")
    F.CreateHeaderDividerAbove(mouseoverHeader)

    local mouseoverSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mouseoverSub:SetPoint("TOPLEFT", mouseoverHeader, "BOTTOMLEFT", 0, -4)
    mouseoverSub:SetWidth(600)
    mouseoverSub:SetJustifyH("LEFT")
    mouseoverSub:SetText("Configure the mouseover highlight border that appears when you hover MSUF unitframes.")

    -- Enable/disable mouseover highlight
    highlightEnableCheck = CreateFrame("CheckButton", "MSUF_Colors_HighlightEnableCheck", content, "UICheckButtonTemplate")
    highlightEnableCheck:SetPoint("TOPLEFT", mouseoverSub, "BOTTOMLEFT", 0, -12)

    if not highlightEnableCheck.text then
        highlightEnableCheck.text = highlightEnableCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        highlightEnableCheck.text:SetPoint("LEFT", highlightEnableCheck, "RIGHT", 2, 0)
    end
    highlightEnableCheck.text:SetText("Enable mouseover highlight")

    local highlightColorLabel
    local highlightColorSwatch

    UpdateHighlightControls = function()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local enabled = (MSUF_DB.general.highlightEnabled ~= false)

        if highlightEnableCheck then
            highlightEnableCheck:SetChecked(enabled)
            F.ApplyToggleGreyout(highlightEnableCheck, enabled)
        end

        local a = enabled and 1 or 0.35
        if highlightColorLabel then highlightColorLabel:SetAlpha(a) end
        if highlightColorSwatch then
            highlightColorSwatch:SetAlpha(a)
            highlightColorSwatch:EnableMouse(enabled)
        end
        if highlightColorTex then highlightColorTex:SetAlpha(a) end
    end

    highlightEnableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.highlightEnabled = self:GetChecked() and true or false
        if UpdateHighlightControls then UpdateHighlightControls() end
        if UpdateAllHighlightColors then
            UpdateAllHighlightColors()
        end
        if ns and ns.MSUF_FixMouseoverHighlightBindings then
            ns.MSUF_FixMouseoverHighlightBindings()
        end
    end)

    -- Mouseover highlight color (Colorpicker)
    highlightColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    highlightColorLabel:SetPoint("TOPLEFT", highlightEnableCheck, "BOTTOMLEFT", 0, -12)
    highlightColorLabel:SetText("Mouseover highlight color")

    highlightColorSwatch = CreateFrame("Button", "MSUF_Colors_HighlightColorSwatch", content)
    highlightColorSwatch:SetSize(32, 16)
    highlightColorSwatch:SetPoint("TOPLEFT", highlightColorLabel, "BOTTOMLEFT", 0, -8)

    highlightColorTex = highlightColorSwatch:CreateTexture(nil, "ARTWORK")
    highlightColorTex:SetAllPoints()

    F.GetHighlightColor = function()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        if type(g.highlightColor) == "table" and g.highlightColor[1] and g.highlightColor[2] and g.highlightColor[3] then
            return g.highlightColor[1], g.highlightColor[2], g.highlightColor[3]
        end

        local key = (type(g.highlightColor) == "string" and g.highlightColor:lower()) or "white"
        local colors = MSUF_FONT_COLORS

        if colors and colors[key] then
            local c = colors[key]
            return c[1], c[2], c[3]
        end

        if colors and colors.white then
            local c = colors.white
            return c[1], c[2], c[3]
        end

        return 1, 1, 1
    end

    F.SetHighlightColor = function(r, g, b)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local gdb = MSUF_DB.general

        gdb.highlightColor = { r, g, b }

        if highlightColorTex then
            highlightColorTex:SetColorTexture(r, g, b)
        end

        if UpdateAllHighlightColors then
            UpdateAllHighlightColors()
        end
        if ns and ns.MSUF_FixMouseoverHighlightBindings then
            ns.MSUF_FixMouseoverHighlightBindings()
        end
    end

    highlightColorSwatch:SetScript("OnClick", function()
        local r, g, b = F.GetHighlightColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            F.SetHighlightColor(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = F.GetHighlightColor()
        highlightColorTex:SetColorTexture(r, g, b)
    end

    if UpdateHighlightControls then UpdateHighlightControls() end

    -- Mouseover highlight is now the lowest control for dynamic height
    lastControl = highlightColorSwatch


--------------------------------------------------
-- Gameplay (Combat state text colors)
--------------------------------------------------
local gameplayHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
gameplayHeader:SetPoint("TOPLEFT", highlightColorSwatch, "BOTTOMLEFT", 0, -44)
gameplayHeader:SetText("Gameplay")
F.CreateHeaderDividerAbove(gameplayHeader)

local gameplaySub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
gameplaySub:SetPoint("TOPLEFT", gameplayHeader, "BOTTOMLEFT", 0, -4)
gameplaySub:SetWidth(600)
gameplaySub:SetJustifyH("LEFT")
gameplaySub:SetText("Configure colors used by Gameplay overlays (Combat Timer, Combat Enter/Leave text, Crosshair range).")

local combatTimerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
combatTimerLabel:SetPoint("TOPLEFT", gameplaySub, "BOTTOMLEFT", 0, -12)
combatTimerLabel:SetText("Combat timer text color")

-- Shown when the corresponding Gameplay option is disabled
local combatTimerOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
combatTimerOffText:SetPoint("LEFT", combatTimerLabel, "RIGHT", 10, 0)
combatTimerOffText:SetText("Turned Off in Gameplay")
combatTimerOffText:Hide()

local combatTimerSwatch = CreateFrame("Button", "MSUF_Colors_CombatTimerColorSwatch", content)
combatTimerSwatch:SetSize(32, 16)
combatTimerSwatch:SetPoint("TOPLEFT", combatTimerLabel, "BOTTOMLEFT", 0, -8)
local combatTimerTex = combatTimerSwatch:CreateTexture(nil, "ARTWORK")
combatTimerTex:SetAllPoints()

local combatEnterLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
combatEnterLabel:SetPoint("TOPLEFT", combatTimerSwatch, "BOTTOMLEFT", 0, -12)
combatEnterLabel:SetText("Combat Enter text color")

-- Shown when Combat Enter/Leave text is disabled in Gameplay
local combatStateOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
combatStateOffText:SetPoint("LEFT", combatEnterLabel, "RIGHT", 10, 0)
combatStateOffText:SetText("Turned Off in Gameplay")
combatStateOffText:Hide()

local combatEnterSwatch = CreateFrame("Button", "MSUF_Colors_CombatEnterColorSwatch", content)
combatEnterSwatch:SetSize(32, 16)
combatEnterSwatch:SetPoint("TOPLEFT", combatEnterLabel, "BOTTOMLEFT", 0, -8)
local combatEnterTex = combatEnterSwatch:CreateTexture(nil, "ARTWORK")
combatEnterTex:SetAllPoints()

local combatLeaveLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
combatLeaveLabel:SetPoint("TOPLEFT", combatEnterSwatch, "BOTTOMLEFT", 0, -12)
combatLeaveLabel:SetText("Combat Leave text color")

local combatLeaveSwatch = CreateFrame("Button", "MSUF_Colors_CombatLeaveColorSwatch", content)
combatLeaveSwatch:SetSize(32, 16)
combatLeaveSwatch:SetPoint("TOPLEFT", combatLeaveLabel, "BOTTOMLEFT", 0, -8)
local combatLeaveTex = combatLeaveSwatch:CreateTexture(nil, "ARTWORK")
combatLeaveTex:SetAllPoints()

local combatColorSyncCheck = CreateFrame("CheckButton", "MSUF_Colors_CombatStateColorSyncCheck", content, "UICheckButtonTemplate")
combatColorSyncCheck:SetPoint("LEFT", combatLeaveLabel, "RIGHT", 16, 0)

if not combatColorSyncCheck.text then
    combatColorSyncCheck.text = combatColorSyncCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    combatColorSyncCheck.text:SetPoint("LEFT", combatColorSyncCheck, "RIGHT", 2, 0)
end
combatColorSyncCheck.text:SetText("Sync")

-- Forward refs so UpdateGameplay* can grey/disable Reset buttons
local combatTimerResetBtn
local combatStateResetBtn
local crosshairResetBtn

F.EnsureGameplayDB = function()
    EnsureDB()
    MSUF_DB.gameplay = MSUF_DB.gameplay or {}
    local g = MSUF_DB.gameplay
    if type(g.combatTimerColor) ~= "table" then
        -- Default matches legacy (white timer text).
        g.combatTimerColor = { 1, 1, 1 }
    end
    if type(g.combatStateEnterColor) ~= "table" then
        g.combatStateEnterColor = { 1, 1, 1 }
    end
    if type(g.combatStateLeaveColor) ~= "table" then
        g.combatStateLeaveColor = { 0.7, 0.7, 0.7 }
    end
    if g.combatStateColorSync == nil then
        g.combatStateColorSync = false
    end
    -- Crosshair range colors (Gameplay crosshair)
    if type(g.crosshairInRangeColor) ~= "table" then
        g.crosshairInRangeColor = { 0, 1, 0 } -- default green
    end
    if type(g.crosshairOutRangeColor) ~= "table" then
        g.crosshairOutRangeColor = { 1, 0, 0 } -- default red
    end
    return g
end


-- Read Gameplay toggles from SavedVariables (Gameplay module defaults are FALSE).
F.IsGameplayToggleEnabled = function(key)
    EnsureDB()
    local gdb = (MSUF_DB and MSUF_DB.gameplay) or {}
    return (gdb[key] == true)
end

F.SetFSAlpha = function(fs, enabled)
    if fs and fs.SetAlpha then
        fs:SetAlpha(enabled and 1 or 0.35)
    end
end

F.SetSwatchEnabled = function(btn, enabled)
    if not btn then return end
    if btn.EnableMouse then btn:EnableMouse(enabled and true or false) end
    if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.35) end
end

F.SetButtonEnabled = function(btn, enabled)
    if not btn then return end
    if btn.Enable and btn.Disable then
        if enabled then btn:Enable() else btn:Disable() end
    elseif btn.SetEnabled then
        btn:SetEnabled(enabled and true or false)
    end
    if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.35) end
end

F.GetCombatTimerColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.combatTimerColor
    return (t and t[1]) or 1, (t and t[2]) or 1, (t and t[3]) or 1
end

F.GetCombatStateEnterColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.combatStateEnterColor
    return (t and t[1]) or 1, (t and t[2]) or 1, (t and t[3]) or 1
end

F.GetCombatStateLeaveColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.combatStateLeaveColor
    return (t and t[1]) or 0.7, (t and t[2]) or 0.7, (t and t[3]) or 0.7
end

F.GetCrosshairInRangeColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.crosshairInRangeColor
    return (t and t[1]) or 0, (t and t[2]) or 1, (t and t[3]) or 0
end

F.GetCrosshairOutRangeColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.crosshairOutRangeColor
    return (t and t[1]) or 1, (t and t[2]) or 0, (t and t[3]) or 0
end

F.UpdateGameplayCombatColorControls = function()
    local g = F.EnsureGameplayDB()

    -- Feature toggles live in the Gameplay menu; if a feature is OFF there,
    -- the corresponding color controls are greyed out here to avoid confusion.
    local timerOn = F.IsGameplayToggleEnabled("enableCombatTimer")
    local stateOn = F.IsGameplayToggleEnabled("enableCombatStateText")

    if combatTimerOffText then combatTimerOffText:SetShown(not timerOn) end
    if combatStateOffText then combatStateOffText:SetShown(not stateOn) end

    -- Combat Timer swatch
    F.SetFSAlpha(combatTimerLabel, timerOn)
    F.SetSwatchEnabled(combatTimerSwatch, timerOn)
    F.SetButtonEnabled(combatTimerResetBtn, timerOn)

    local tr, tg, tb = F.GetCombatTimerColor()
    if combatTimerTex then
        combatTimerTex:SetColorTexture(tr, tg, tb)
        combatTimerTex:SetAlpha(timerOn and 1 or 0.35)
    end

    -- Combat Enter/Leave swatches
    F.SetFSAlpha(combatEnterLabel, stateOn)
    F.SetSwatchEnabled(combatEnterSwatch, stateOn)
    F.SetButtonEnabled(combatStateResetBtn, stateOn)

    local er, eg, eb = F.GetCombatStateEnterColor()
    local lr, lg, lb = F.GetCombatStateLeaveColor()

    if g.combatStateColorSync then
        lr, lg, lb = er, eg, eb
    end

    if combatEnterTex then
        combatEnterTex:SetColorTexture(er, eg, eb)
        combatEnterTex:SetAlpha(stateOn and 1 or 0.35)
    end

    if combatColorSyncCheck then
        combatColorSyncCheck:SetChecked(g.combatStateColorSync and true or false)
        if stateOn and combatColorSyncCheck.Enable then
            combatColorSyncCheck:Enable()
        elseif combatColorSyncCheck.Disable then
            combatColorSyncCheck:Disable()
        end
        F.ApplyToggleGreyout(combatColorSyncCheck, stateOn)
    end

    -- Leave color is disabled when Sync is enabled (and also when the feature itself is off).
    local leaveEnabled = stateOn and (not g.combatStateColorSync)
    local a = leaveEnabled and 1 or 0.35

    if combatLeaveLabel then combatLeaveLabel:SetAlpha(a) end
    if combatLeaveSwatch then
        combatLeaveSwatch:SetAlpha(a)
        combatLeaveSwatch:EnableMouse(leaveEnabled)
    end
    if combatLeaveTex then
        combatLeaveTex:SetColorTexture(lr, lg, lb)
        combatLeaveTex:SetAlpha(a)
    end
end

F.SetCombatTimerColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.combatTimerColor = { r, gCol, bCol }
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.SetCombatStateEnterColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.combatStateEnterColor = { r, gCol, bCol }
    if g.combatStateColorSync then
        g.combatStateLeaveColor = { r, gCol, bCol }
    end
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.SetCombatStateLeaveColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    if g.combatStateColorSync then
        return
    end
    g.combatStateLeaveColor = { r, gCol, bCol }
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end


-- Reset buttons (Gameplay colors)
F.ResetGameplayCombatTimerColor = function()
    local g = F.EnsureGameplayDB()
    g.combatTimerColor = { 1, 1, 1 }
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.ResetGameplayCombatStateColors = function()
    local g = F.EnsureGameplayDB()
    g.combatStateEnterColor = { 1, 1, 1 }
    if g.combatStateColorSync then
        g.combatStateLeaveColor = { 1, 1, 1 }
    else
        g.combatStateLeaveColor = { 0.7, 0.7, 0.7 }
    end
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

combatTimerResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
combatTimerResetBtn:SetSize(110, 22)
combatTimerResetBtn:SetPoint("LEFT", combatTimerSwatch, "RIGHT", 12, 0)
combatTimerResetBtn:SetText("Reset")
combatTimerResetBtn:SetScript("OnClick", function()
    F.ResetGameplayCombatTimerColor()
end)

combatStateResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
combatStateResetBtn:SetSize(110, 22)
combatStateResetBtn:SetPoint("LEFT", combatEnterSwatch, "RIGHT", 12, 0)
combatStateResetBtn:SetText("Reset")
combatStateResetBtn:SetScript("OnClick", function()
    F.ResetGameplayCombatStateColors()
end)

combatTimerSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCombatTimerColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCombatTimerColor(nr, ng, nb)
    end)
end)

combatEnterSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCombatStateEnterColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCombatStateEnterColor(nr, ng, nb)
    end)
end)

combatLeaveSwatch:SetScript("OnClick", function()
    local g = F.EnsureGameplayDB()
    if g.combatStateColorSync then
        return
    end
    local r, gCol, bCol = F.GetCombatStateLeaveColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCombatStateLeaveColor(nr, ng, nb)
    end)
end)

combatColorSyncCheck:SetScript("OnClick", function(self)
    local g = F.EnsureGameplayDB()
    g.combatStateColorSync = self:GetChecked() and true or false
    if g.combatStateColorSync then
        local r, gCol, bCol = F.GetCombatStateEnterColor()
        g.combatStateLeaveColor = { r, gCol, bCol }
    end
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end)


-- Crosshair range colors (Gameplay)
local crosshairInLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
crosshairInLabel:SetPoint("TOPLEFT", combatLeaveSwatch, "BOTTOMLEFT", 0, -18)
crosshairInLabel:SetText("Crosshair in-range color")

-- Shown when Crosshair melee-range coloring is disabled in Gameplay
local crosshairOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
crosshairOffText:SetPoint("LEFT", crosshairInLabel, "RIGHT", 10, 0)
crosshairOffText:SetText("Turned Off in Gameplay")
crosshairOffText:Hide()

local crosshairInSwatch = CreateFrame("Button", "MSUF_Colors_CrosshairInRangeColorSwatch", content)
crosshairInSwatch:SetSize(32, 16)
crosshairInSwatch:SetPoint("TOPLEFT", crosshairInLabel, "BOTTOMLEFT", 0, -8)
local crosshairInTex = crosshairInSwatch:CreateTexture(nil, "ARTWORK")
crosshairInTex:SetAllPoints()

local crosshairOutLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
crosshairOutLabel:SetPoint("TOPLEFT", crosshairInSwatch, "BOTTOMLEFT", 0, -12)
crosshairOutLabel:SetText("Crosshair out-of-range color")

local crosshairOutSwatch = CreateFrame("Button", "MSUF_Colors_CrosshairOutRangeColorSwatch", content)
crosshairOutSwatch:SetSize(32, 16)
crosshairOutSwatch:SetPoint("TOPLEFT", crosshairOutLabel, "BOTTOMLEFT", 0, -8)
local crosshairOutTex = crosshairOutSwatch:CreateTexture(nil, "ARTWORK")
crosshairOutTex:SetAllPoints()

F.UpdateGameplayCrosshairColorControls = function()
        
    -- Crosshair range colors only matter when:
    --  1) Crosshair is enabled
    --  2) Melee-range coloring is enabled
    local crosshairOn = F.IsGameplayToggleEnabled("enableCombatCrosshair") and F.IsGameplayToggleEnabled("enableCombatCrosshairMeleeRangeColor")

    if crosshairOffText then crosshairOffText:SetShown(not crosshairOn) end

    F.SetFSAlpha(crosshairInLabel, crosshairOn)
    F.SetFSAlpha(crosshairOutLabel, crosshairOn)
    F.SetSwatchEnabled(crosshairInSwatch, crosshairOn)
    F.SetSwatchEnabled(crosshairOutSwatch, crosshairOn)
    F.SetButtonEnabled(crosshairResetBtn, crosshairOn)

    local ir, ig, ib = F.GetCrosshairInRangeColor()
    local or_, og, ob = F.GetCrosshairOutRangeColor()

    if crosshairInTex then
        crosshairInTex:SetColorTexture(ir, ig, ib)
        crosshairInTex:SetAlpha(crosshairOn and 1 or 0.35)
    end
    if crosshairOutTex then
        crosshairOutTex:SetColorTexture(or_, og, ob)
        crosshairOutTex:SetAlpha(crosshairOn and 1 or 0.35)
    end
end

F.SetCrosshairInRangeColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.crosshairInRangeColor = { r, gCol, bCol }
    F.UpdateGameplayCrosshairColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.SetCrosshairOutRangeColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.crosshairOutRangeColor = { r, gCol, bCol }
    F.UpdateGameplayCrosshairColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end


-- Reset buttons (Crosshair range colors)
F.ResetGameplayCrosshairColors = function()
    local g = F.EnsureGameplayDB()
    g.crosshairInRangeColor = { 0, 1, 0 }
    g.crosshairOutRangeColor = { 1, 0, 0 }
    F.UpdateGameplayCrosshairColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

crosshairResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
crosshairResetBtn:SetSize(110, 22)
crosshairResetBtn:SetPoint("LEFT", crosshairInSwatch, "RIGHT", 12, 0)
crosshairResetBtn:SetText("Reset")
crosshairResetBtn:SetScript("OnClick", function()
    F.ResetGameplayCrosshairColors()
end)

crosshairInSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCrosshairInRangeColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCrosshairInRangeColor(nr, ng, nb)
    end)
end)

crosshairOutSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCrosshairOutRangeColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCrosshairOutRangeColor(nr, ng, nb)
    end)
end)

-- Initialize swatches + enable states
F.UpdateGameplayCombatColorControls()
F.UpdateGameplayCrosshairColorControls()

-- Gameplay section is now the lowest control for dynamic height
lastControl = crosshairOutSwatch


--------------------------------------------------
-- Power colors (Unitframe power bar)
--------------------------------------------------
local powerHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
powerHeader:SetPoint("TOPLEFT", crosshairOutSwatch, "BOTTOMLEFT", 0, -44)
powerHeader:SetText("Power bar colors")
F.CreateHeaderDividerAbove(powerHeader)

local powerSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
powerSub:SetPoint("TOPLEFT", powerHeader, "BOTTOMLEFT", 0, -4)
powerSub:SetWidth(600)
powerSub:SetJustifyH("LEFT")
powerSub:SetText("Configure custom colors for power resources used by MSUF power bars.")

local powerTypeDrop = CreateFrame("Frame", "MSUF_Colors_PowerTypeDropdown", content, "UIDropDownMenuTemplate")
powerTypeDrop:SetPoint("TOPLEFT", powerSub, "BOTTOMLEFT", -16, -8)
UIDropDownMenu_SetWidth(powerTypeDrop, 220)
MSUF_ExpandDropdownClickArea(powerTypeDrop)

local powerColorSwatch = CreateFrame("Button", "MSUF_Colors_PowerColorSwatch", content)
powerColorSwatch:SetSize(32, 16)
powerColorSwatch:SetPoint("LEFT", powerTypeDrop, "RIGHT", 18, 2)
local powerColorTex = powerColorSwatch:CreateTexture(nil, "ARTWORK")
powerColorTex:SetAllPoints()

local powerColorResetBtn = CreateFrame("Button", "MSUF_Colors_PowerColorResetBtn", content, "UIPanelButtonTemplate")
powerColorResetBtn:SetText("Reset")
powerColorResetBtn:SetSize(70, 18)
powerColorResetBtn:SetPoint("LEFT", powerColorSwatch, "RIGHT", 10, 0)

-- Common power tokens (keep simple, but cover modern classes)
local POWER_TOKEN_OPTIONS = {
    { token = "MANA",        label = "Mana" },
    { token = "RAGE",        label = "Rage" },
    { token = "ENERGY",      label = "Energy" },
    { token = "FOCUS",       label = "Focus" },
    { token = "RUNIC_POWER", label = "Runic Power" },
    { token = "INSANITY",    label = "Insanity" },
    { token = "FURY",        label = "Fury" },
    { token = "PAIN",        label = "Pain" },
    { token = "ESSENCE",     label = "Essence" },
}

F.EnsurePowerColorsDB = function()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if type(g.powerColorOverrides) ~= "table" then
        g.powerColorOverrides = {}
    end
    return g
end

F.GetDefaultPowerColorForToken = function(token)
    local col = (PowerBarColor and token and PowerBarColor[token]) or nil
    if type(col) == "table" then
        local r = col.r or col[1]
        local g = col.g or col[2]
        local b = col.b or col[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return 0.8, 0.8, 0.8
end

F.GetEffectivePowerColorForToken = function(token)
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local ov = g and g.powerColorOverrides
    local t = (type(ov) == "table" and token) and ov[token] or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, true
        end
    end
    local dr, dg, db = F.GetDefaultPowerColorForToken(token)
    return dr, dg, db, false
end

F.UpdatePowerColorControls = function()
    local token = powerTypeDrop._msufSelectedToken or "MANA"
    local r, gCol, bCol, hasOverride = F.GetEffectivePowerColorForToken(token)
    if powerColorTex then
        powerColorTex:SetColorTexture(r, gCol, bCol)
    end
    if powerColorResetBtn then
        powerColorResetBtn:SetEnabled(hasOverride)
        powerColorResetBtn:SetAlpha(hasOverride and 1 or 0.35)
    end
end

F.PowerTypeDropdown_Initialize = function(self, level)
    local selected = powerTypeDrop._msufSelectedToken or "MANA"
    for _, opt in ipairs(POWER_TOKEN_OPTIONS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text  = opt.label
        info.value = opt.token
        info.func  = function()
            powerTypeDrop._msufSelectedToken = opt.token
            UIDropDownMenu_SetSelectedValue(powerTypeDrop, opt.token)
            UIDropDownMenu_SetText(powerTypeDrop, opt.label)
            F.UpdatePowerColorControls()
        end
        info.checked = (opt.token == selected)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(powerTypeDrop, F.PowerTypeDropdown_Initialize)
powerTypeDrop._msufSelectedToken = powerTypeDrop._msufSelectedToken or "MANA"
UIDropDownMenu_SetSelectedValue(powerTypeDrop, powerTypeDrop._msufSelectedToken)
-- Set initial text
do
    local txtLabel = "Mana"
    for _, opt in ipairs(POWER_TOKEN_OPTIONS) do
        if opt.token == powerTypeDrop._msufSelectedToken then
            txtLabel = opt.label
            break
        end
    end
    UIDropDownMenu_SetText(powerTypeDrop, txtLabel)
end

powerColorSwatch:SetScript("OnClick", function()
    local token = powerTypeDrop._msufSelectedToken or "MANA"
    local r, gCol, bCol = F.GetEffectivePowerColorForToken(token)
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        local g = F.EnsurePowerColorsDB()
        g.powerColorOverrides[token] = { nr, ng, nb }
        F.UpdatePowerColorControls()
        PushVisualUpdates()
    end)
end)

powerColorResetBtn:SetScript("OnClick", function()
    local token = powerTypeDrop._msufSelectedToken or "MANA"
    F.EnsurePowerColorsDB()
    if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.powerColorOverrides) == "table" then
        MSUF_DB.general.powerColorOverrides[token] = nil
    end
    F.UpdatePowerColorControls()
    PushVisualUpdates()
end)

F.UpdatePowerColorControls()

-- Power colors is now the lowest control for dynamic height
lastControl = powerColorResetBtn




--------------------------------------------------
-- Auras (Auras 2.0)
--------------------------------------------------
local aurasHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
aurasHeader:SetPoint("TOPLEFT", powerTypeDrop, "BOTTOMLEFT", 16, -34)
aurasHeader:SetText("Auras")
F.CreateHeaderDividerAbove(aurasHeader)

local aurasSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
aurasSub:SetPoint("TOPLEFT", aurasHeader, "BOTTOMLEFT", 0, -4)
aurasSub:SetWidth(600)
aurasSub:SetJustifyH("LEFT")
aurasSub:SetText("Configure colors used by Auras 2.0 (own highlight borders, advanced filter borders) and stack count text.")

local auraBuffLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraBuffLabel:SetPoint("TOPLEFT", aurasSub, "BOTTOMLEFT", 0, -12)
auraBuffLabel:SetText("Own buff highlight color")

local auraBuffSwatch = CreateFrame("Button", "MSUF_Colors_AuraOwnBuffHighlightSwatch", content)
auraBuffSwatch:SetSize(32, 16)
auraBuffSwatch:SetPoint("TOPLEFT", auraBuffLabel, "BOTTOMLEFT", 0, -8)
local auraBuffTex = auraBuffSwatch:CreateTexture(nil, "ARTWORK")
auraBuffTex:SetAllPoints()

local auraDebuffLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraDebuffLabel:SetPoint("TOPLEFT", auraBuffSwatch, "BOTTOMLEFT", 0, -12)
auraDebuffLabel:SetText("Own debuff highlight color")

local auraDebuffSwatch = CreateFrame("Button", "MSUF_Colors_AuraOwnDebuffHighlightSwatch", content)
auraDebuffSwatch:SetSize(32, 16)
auraDebuffSwatch:SetPoint("TOPLEFT", auraDebuffLabel, "BOTTOMLEFT", 0, -8)
local auraDebuffTex = auraDebuffSwatch:CreateTexture(nil, "ARTWORK")
auraDebuffTex:SetAllPoints()

local auraStacksLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraStacksLabel:SetPoint("TOPLEFT", auraDebuffSwatch, "BOTTOMLEFT", 0, -12)
auraStacksLabel:SetText("Stack count text color")

local auraStacksSwatch = CreateFrame("Button", "MSUF_Colors_AuraStackCountSwatch", content)
auraStacksSwatch:SetSize(32, 16)
auraStacksSwatch:SetPoint("TOPLEFT", auraStacksLabel, "BOTTOMLEFT", 0, -8)
local auraStacksTex = auraStacksSwatch:CreateTexture(nil, "ARTWORK")
auraStacksTex:SetAllPoints()

local auraResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
auraResetBtn:SetSize(110, 22)
auraResetBtn:SetPoint("LEFT", auraStacksSwatch, "RIGHT", 12, 0)
auraResetBtn:SetText("Reset")


-- Dispellable border highlight color
local auraDispelLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraDispelLabel:SetPoint("TOPLEFT", auraStacksSwatch, "BOTTOMLEFT", 0, -12)
auraDispelLabel:SetText("Dispellable/Dispel border highlight color")

local auraDispelSwatch = CreateFrame("Button", "MSUF_Colors_AuraDispelBorderSwatch", content)
auraDispelSwatch:SetSize(32, 16)
auraDispelSwatch:SetPoint("TOPLEFT", auraDispelLabel, "BOTTOMLEFT", 0, -8)
local auraDispelTex = auraDispelSwatch:CreateTexture(nil, "ARTWORK")
auraDispelTex:SetAllPoints()

-- Stealable/Purge border highlight color
local auraStealLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraStealLabel:SetPoint("TOPLEFT", auraDispelSwatch, "BOTTOMLEFT", 0, -12)
auraStealLabel:SetText("Stealable/Purge border highlight color")

local auraStealSwatch = CreateFrame("Button", "MSUF_Colors_AuraStealableBorderSwatch", content)
auraStealSwatch:SetSize(32, 16)
auraStealSwatch:SetPoint("TOPLEFT", auraStealLabel, "BOTTOMLEFT", 0, -8)
local auraStealTex = auraStealSwatch:CreateTexture(nil, "ARTWORK")
auraStealTex:SetAllPoints()


-- Aura cooldown text colors (DurationObject step curve)
local auraCDSafeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraCDSafeLabel:SetPoint("TOPLEFT", aurasSub, "BOTTOMLEFT", 360, -12)
auraCDSafeLabel:SetText("Cooldown text: Safe")

local auraCDSafeSwatch = CreateFrame("Button", "MSUF_Colors_AuraCooldownSafeSwatch", content)
auraCDSafeSwatch:SetSize(32, 16)
auraCDSafeSwatch:SetPoint("TOPLEFT", auraCDSafeLabel, "BOTTOMLEFT", 0, -8)
local auraCDSafeTex = auraCDSafeSwatch:CreateTexture(nil, "ARTWORK")
auraCDSafeTex:SetAllPoints()

local auraCDWarnLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraCDWarnLabel:SetPoint("TOPLEFT", auraCDSafeLabel, "BOTTOMLEFT", 0, -32)
auraCDWarnLabel:SetText("Cooldown text: Warning")

local auraCDWarnSwatch = CreateFrame("Button", "MSUF_Colors_AuraCooldownWarningSwatch", content)
auraCDWarnSwatch:SetSize(32, 16)
auraCDWarnSwatch:SetPoint("TOPLEFT", auraCDWarnLabel, "BOTTOMLEFT", 0, -8)
local auraCDWarnTex = auraCDWarnSwatch:CreateTexture(nil, "ARTWORK")
auraCDWarnTex:SetAllPoints()

local auraCDUrgentLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraCDUrgentLabel:SetPoint("TOPLEFT", auraCDWarnLabel, "BOTTOMLEFT", 0, -32)
auraCDUrgentLabel:SetText("Cooldown text: Urgent")

local auraCDUrgentSwatch = CreateFrame("Button", "MSUF_Colors_AuraCooldownUrgentSwatch", content)
auraCDUrgentSwatch:SetSize(32, 16)
auraCDUrgentSwatch:SetPoint("TOPLEFT", auraCDUrgentLabel, "BOTTOMLEFT", 0, -8)
local auraCDUrgentTex = auraCDUrgentSwatch:CreateTexture(nil, "ARTWORK")
auraCDUrgentTex:SetAllPoints()

local auraCDResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
auraCDResetBtn:SetSize(110, 22)
auraCDResetBtn:SetPoint("LEFT", auraCDUrgentSwatch, "RIGHT", 12, 0)
auraCDResetBtn:SetText("Reset")

F.EnsureAurasColorsDB = function()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if type(g.aurasOwnBuffHighlightColor) ~= "table" then
        g.aurasOwnBuffHighlightColor = { 1.0, 0.85, 0.2 } -- legacy gold
    end
    if type(g.aurasOwnDebuffHighlightColor) ~= "table" then
        g.aurasOwnDebuffHighlightColor = { 1.0, 0.85, 0.2 } -- legacy gold
    end
    if type(g.aurasStackCountColor) ~= "table" then
        g.aurasStackCountColor = { 1, 1, 1 } -- white
    end
    if type(g.aurasDispelBorderColor) ~= "table" then
        g.aurasDispelBorderColor = { 0.2, 0.6, 1.0 } -- bright blue
    end
    if type(g.aurasStealableBorderColor) ~= "table" then
        g.aurasStealableBorderColor = { 0.0, 0.75, 1.0 } -- cyan
    end
    if type(g.aurasCooldownTextWarningColor) ~= "table" then
        g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 } -- warning (yellow)
    end
    if type(g.aurasCooldownTextUrgentColor) ~= "table" then
        g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 } -- urgent (orange/red)
    end
    return g
end

F.GetAurasOwnBuffHighlightColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasOwnBuffHighlightColor
    return t[1] or 1.0, t[2] or 0.85, t[3] or 0.2
end

F.GetAurasOwnDebuffHighlightColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasOwnDebuffHighlightColor
    return t[1] or 1.0, t[2] or 0.85, t[3] or 0.2
end

F.GetAurasStackCountColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasStackCountColor
    return t[1] or 1, t[2] or 1, t[3] or 1
end


F.GetAurasDispelBorderColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasDispelBorderColor
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 0.2, 0.6, 1.0
end

F.GetAurasStealableBorderColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasStealableBorderColor
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 0.0, 0.75, 1.0
end

F.GetAurasCooldownTextSafeColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasCooldownTextSafeColor
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return GetGlobalFontColor()
end

F.GetAurasCooldownTextWarningColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasCooldownTextWarningColor
    return (t[1] or 1.00), (t[2] or 0.85), (t[3] or 0.20)
end

F.GetAurasCooldownTextUrgentColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasCooldownTextUrgentColor
    return (t[1] or 1.00), (t[2] or 0.55), (t[3] or 0.10)
end

F.PushAuras2ColorRefresh = function()
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
    if PushVisualUpdates then
        PushVisualUpdates()
    end
end

-- Live recolor helper for Aura cooldown text (preview + active icons)
F.ForceAurasCooldownTextRecolor = function()
    if type(_G.MSUF_A2_ForceCooldownTextRecolor) == 'function' then
        _G.MSUF_A2_ForceCooldownTextRecolor()
    end
end

F.UpdateAurasColorControls = function()
    local br, bg, bb = F.GetAurasOwnBuffHighlightColor()
    local dr, dg, db = F.GetAurasOwnDebuffHighlightColor()
    local sr, sg, sb = F.GetAurasStackCountColor()
    local pr, pg, pb = F.GetAurasDispelBorderColor()
    local tr, tg, tb = F.GetAurasStealableBorderColor()
    local cr, cg, cb = F.GetAurasCooldownTextSafeColor()
    local wr, wg, wb = F.GetAurasCooldownTextWarningColor()
    local ur, ug, ub = F.GetAurasCooldownTextUrgentColor()
    if auraBuffTex then auraBuffTex:SetColorTexture(br, bg, bb) end
    if auraDebuffTex then auraDebuffTex:SetColorTexture(dr, dg, db) end
    if auraStacksTex then auraStacksTex:SetColorTexture(sr, sg, sb) end
    if auraDispelTex then auraDispelTex:SetColorTexture(pr, pg, pb) end
    if auraStealTex then auraStealTex:SetColorTexture(tr, tg, tb) end
    if auraCDSafeTex then auraCDSafeTex:SetColorTexture(cr, cg, cb) end
    if auraCDWarnTex then auraCDWarnTex:SetColorTexture(wr, wg, wb) end
    if auraCDUrgentTex then auraCDUrgentTex:SetColorTexture(ur, ug, ub) end


    -- Bucket-coloring master toggle: when disabled, only Safe should be configurable.
    EnsureDB()
    local gg = (MSUF_DB and MSUF_DB.general) or nil
    local bucketsEnabled = not (gg and gg.aurasCooldownTextUseBuckets == false)
    local a = bucketsEnabled and 1 or 0.35

    if auraCDWarnSwatch then
        auraCDWarnSwatch:EnableMouse(bucketsEnabled)
        auraCDWarnSwatch:SetAlpha(a)
    end
    if auraCDWarnLabel then
        auraCDWarnLabel:SetAlpha(a)
    end

    if auraCDUrgentSwatch then
        auraCDUrgentSwatch:EnableMouse(bucketsEnabled)
        auraCDUrgentSwatch:SetAlpha(a)
    end
    if auraCDUrgentLabel then
        auraCDUrgentLabel:SetAlpha(a)
    end
end

F.SetAurasOwnBuffHighlightColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasOwnBuffHighlightColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end

F.SetAurasOwnDebuffHighlightColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasOwnDebuffHighlightColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end

F.SetAurasStackCountColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasStackCountColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end


F.SetAurasDispelBorderColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasDispelBorderColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end

F.SetAurasStealableBorderColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasStealableBorderColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end

F.SetAurasCooldownTextSafeColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    if r == nil or gCol == nil or bCol == nil then
        g.aurasCooldownTextSafeColor = nil -- fallback to Global font color
    else
        g.aurasCooldownTextSafeColor = { r, gCol, bCol }
    end
    F.UpdateAurasColorControls()
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.PushAuras2ColorRefresh()
end

F.SetAurasCooldownTextWarningColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasCooldownTextWarningColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.PushAuras2ColorRefresh()
end

F.SetAurasCooldownTextUrgentColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasCooldownTextUrgentColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.PushAuras2ColorRefresh()
end

auraBuffSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasOwnBuffHighlightColor(1.0, 0.85, 0.2)
        return
    end
    local r, gCol, bCol = F.GetAurasOwnBuffHighlightColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasOwnBuffHighlightColor(nr, ng, nb)
    end)
end)

auraDebuffSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasOwnDebuffHighlightColor(1.0, 0.85, 0.2)
        return
    end
    local r, gCol, bCol = F.GetAurasOwnDebuffHighlightColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasOwnDebuffHighlightColor(nr, ng, nb)
    end)
end)

auraStacksSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasStackCountColor(1, 1, 1)
        return
    end
    local r, gCol, bCol = F.GetAurasStackCountColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasStackCountColor(nr, ng, nb)
    end)
end)

auraDispelSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasDispelBorderColor(0.2, 0.6, 1.0)
        return
    end
    local r, gCol, bCol = F.GetAurasDispelBorderColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasDispelBorderColor(nr, ng, nb)
    end)
end)

auraStealSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasStealableBorderColor(0.0, 0.75, 1.0)
        return
    end
    local r, gCol, bCol = F.GetAurasStealableBorderColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasStealableBorderColor(nr, ng, nb)
    end)
end)

auraCDSafeSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasCooldownTextSafeColor(nil, nil, nil) -- reset to Global font color
        return
    end
    local r, gCol, bCol = F.GetAurasCooldownTextSafeColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasCooldownTextSafeColor(nr, ng, nb)
    end)
end)

auraCDWarnSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasCooldownTextWarningColor(1.00, 0.85, 0.20)
        return
    end
    local r, gCol, bCol = F.GetAurasCooldownTextWarningColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasCooldownTextWarningColor(nr, ng, nb)
    end)
end)

auraCDUrgentSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasCooldownTextUrgentColor(1.00, 0.55, 0.10)
        return
    end
    local r, gCol, bCol = F.GetAurasCooldownTextUrgentColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasCooldownTextUrgentColor(nr, ng, nb)
    end)
end)

auraCDResetBtn:SetScript("OnClick", function()
    F.EnsureAurasColorsDB()
    MSUF_DB.general.aurasCooldownTextSafeColor = nil
    MSUF_DB.general.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
    MSUF_DB.general.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end)


auraResetBtn:SetScript("OnClick", function()
    F.EnsureAurasColorsDB()
    MSUF_DB.general.aurasOwnBuffHighlightColor = { 1.0, 0.85, 0.2 }
    MSUF_DB.general.aurasOwnDebuffHighlightColor = { 1.0, 0.85, 0.2 }
    MSUF_DB.general.aurasStackCountColor = { 1, 1, 1 }
    MSUF_DB.general.aurasDispelBorderColor = { 0.2, 0.6, 1.0 }
    MSUF_DB.general.aurasStealableBorderColor = { 0.0, 0.75, 1.0 }
    MSUF_DB.general.aurasCooldownTextSafeColor = nil
    MSUF_DB.general.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
    MSUF_DB.general.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end)

F.UpdateAurasColorControls()

-- Auras section is now the lowest control for dynamic height
lastControl = auraStealSwatch

    --------------------------------------------------
    -- F.Refresh function
    --------------------------------------------------
    F.Refresh = function()
        -- Global font
        local fr, fg, fb = GetGlobalFontColor()
        if fontSwatchTex then
            fontSwatchTex:SetColorTexture(fr, fg, fb)
        end

        -- Class colors + Label-Kontrast
        for _, token in ipairs(CLASS_TOKENS) do
            local tex   = classSwatches[token]
            local label = classLabels[token]
            if tex then
                local r, g, b = GetClassColor(token)
                tex:SetColorTexture(r, g, b)
                F.SetLabelContrast(label, r, g, b)
            end
        end

        -- Class bar background
        if classBgSwatchTex then
            local br, bg, bb = GetClassBarBgColor()
            classBgSwatchTex:SetColorTexture(br, bg, bb)
        end

        -- Bar background tint: optional Match-HP behavior (makes swatch read-only)
        if classBgMatchCheck then
            local match = GetBarBgMatchHP()
            classBgMatchCheck:SetChecked(match)
            if _G.MSUF_Colors_ClassBarBgSwatch and _G.MSUF_Colors_ClassBarBgSwatch.EnableMouse then
                _G.MSUF_Colors_ClassBarBgSwatch:EnableMouse(not match)
                _G.MSUF_Colors_ClassBarBgSwatch:SetAlpha(match and 0.5 or 1)
            end
            if classBgResetBtn and classBgResetBtn.SetEnabled then
                classBgResetBtn:SetEnabled(not match)
            end
        end


        -- Gameplay combat state colors
        if F.UpdateGameplayCombatColorControls then
            F.UpdateGameplayCombatColorControls()
        end

        -- Gameplay crosshair range colors
        if F.UpdateGameplayCrosshairColorControls then
            F.UpdateGameplayCrosshairColorControls()
        end

        

        -- Power bar colors
        if F.UpdatePowerColorControls then
            F.UpdatePowerColorControls()
        end

        -- Auras colors
        if F.UpdateAurasColorControls then
            F.UpdateAurasColorControls()
        end
-- Bar appearance (moved from Bars menu)
        if barModeDrop or darkToneSlider then
            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            barAppearanceRefreshing = true

            -- Refresh unified swatch color (in case profile changed)
            if _G.MSUF_Colors_UnifiedBarSwatch and _G.MSUF_Colors_UnifiedBarSwatch.GetRegions then
                local r, gg, b = (function()
                    local rr, ggg, bb = g.unifiedBarR, g.unifiedBarG, g.unifiedBarB
                    if type(rr) ~= "number" or type(ggg) ~= "number" or type(bb) ~= "number" then
                        rr, ggg, bb = 0.10, 0.60, 0.90
                    end
                    if rr < 0 then rr = 0 elseif rr > 1 then rr = 1 end
                    if ggg < 0 then ggg = 0 elseif ggg > 1 then ggg = 1 end
                    if bb < 0 then bb = 0 elseif bb > 1 then bb = 1 end
                    return rr, ggg, bb
                end)()
                if unifiedTex and unifiedTex.SetColorTexture then
                    unifiedTex:SetColorTexture(r, gg, b)
                end
            end

            if barModeDrop then
                local mode = g.barMode
                if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
                    mode = (g.useClassColors and "class") or "dark"
                    g.barMode = mode
                end
                local label = "Dark Mode (dark black bars)"
                if mode == "class" then
                    label = "Class Color Mode (color HP bars)"
                elseif mode == "unified" then
                    label = "Unified Color Mode (one color for all frames)"
                end
                UIDropDownMenu_SetSelectedValue(barModeDrop, mode)
                UIDropDownMenu_SetText(barModeDrop, label)
            end
if darkToneSlider then
    local pct
    if type(g.darkBarGray) == "number" then
        pct = math.floor(g.darkBarGray * 100 + 0.5)
    else
        local toneKey = g.darkBarTone
        if type(toneKey) ~= "string" or toneKey == "" then
            toneKey = "black"
        end
        if toneKey == "darkgray" then
            pct = 25
        elseif toneKey == "softgray" then
            pct = 45
        else
            pct = 0
        end
    end
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    darkToneSlider:SetValue(pct)
    if UpdateDarkToneValueText then
        UpdateDarkToneValueText(pct)
    end
end

            if UpdateDarkBarControls then UpdateDarkBarControls() end
            if F.UpdateUnifiedBarControls then F.UpdateUnifiedBarControls() end
            barAppearanceRefreshing = false
        end

        -- NPC colors
        if npcFriendlyTex then
            local r1, g1, b1 = GetNPCColor("friendly")
            npcFriendlyTex:SetColorTexture(r1, g1, b1)
        end
        if npcNeutralTex then
            local r2, g2, b2 = GetNPCColor("neutral")
            npcNeutralTex:SetColorTexture(r2, g2, b2)
        end
        if npcEnemyTex then
            local r3, g3, b3 = GetNPCColor("enemy")
            npcEnemyTex:SetColorTexture(r3, g3, b3)
        end
        if npcDeadTex then
            local r4, g4, b4 = GetNPCColor("dead")
            npcDeadTex:SetColorTexture(r4, g4, b4)
        end
        if petFrameTex then
            local pr, pg, pb = GetPetFrameColor()
            petFrameTex:SetColorTexture(pr, pg, pb)
        end

           -- Castbar colors
        if interruptibleTex or nonInterruptibleTex or interruptFeedbackTex then
            if interruptibleTex then
                local r, g2, b2 = GetInterruptibleCastColor()
                interruptibleTex:SetColorTexture(r, g2, b2)
            end
            if nonInterruptibleTex then
                local r, g2, b2 = GetNonInterruptibleCastColor()
                nonInterruptibleTex:SetColorTexture(r, g2, b2)
            end
            if interruptFeedbackTex then
                local r, g2, b2 = GetInterruptFeedbackCastColor()
                interruptFeedbackTex:SetColorTexture(r, g2, b2)
            end
        end
        -- Mouseover highlight (enable + colorpicker)
        if highlightEnableCheck or highlightColorTex then
            if UpdateHighlightControls then
                UpdateHighlightControls()
            else
                EnsureDB()
                local g = MSUF_DB.general or {}
                if highlightEnableCheck then
                    highlightEnableCheck:SetChecked(g.highlightEnabled ~= false)
                end
            end
            if highlightColorTex then
                local hr, hg, hb = F.GetHighlightColor()
                highlightColorTex:SetColorTexture(hr, hg, hb)
            end
        end
end

    --------------------------------------------------
    -- Dynamic content height
    --------------------------------------------------
    F.UpdateContentHeight = function()
        local minHeight = 400
        if not lastControl then
            content:SetHeight(minHeight)
            return
        end

        local bottom = lastControl:GetBottom()
        local top    = content:GetTop()
        if not bottom or not top then
            content:SetHeight(minHeight)
            return
        end

        local padding = 40
        local height  = top - bottom + padding
        if height < minHeight then
            height = minHeight
        end
        content:SetHeight(height)
    end

    --------------------------------------------------
    -- Register as sub-category under the main MSUF panel
    --------------------------------------------------
    if (not panel.__MSUF_SettingsRegistered) and Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
        local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        panel.__MSUF_SettingsRegistered = true
        ns.MSUF_ColorsCategory = subcategory
    elseif InterfaceOptions_AddCategory then
        panel.parent = "Midnight Simple Unit Frames"
        InterfaceOptions_AddCategory(panel)
    end

    panel:SetScript("OnShow", function()
        if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end
        F.Refresh()
        F.UpdateContentHeight()
    end)

    -- Initial refresh
    F.Refresh()
    F.UpdateContentHeight()

    if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end

    panel.__MSUF_ColorsBuilt = true
    return panel
end


-- Lightweight wrapper: register the category at login, but build the heavy UI only when opened.
function ns.MSUF_RegisterColorsOptions(parentCategory)
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory or not parentCategory then
        return ns.MSUF_RegisterColorsOptions_Full(parentCategory)
    end

    local panel = (_G and _G.MSUF_ColorsPanel) or CreateFrame("Frame", "MSUF_ColorsPanel", UIParent)
    panel.name = "Colors"

    -- IMPORTANT: Panels created with UIParent are shown by default.
    -- If we rely on OnShow for first-time build, we must ensure the panel starts hidden,
    -- otherwise the first Settings click may not fire OnShow.
    if not panel.__MSUF_ForceHidden then
        panel.__MSUF_ForceHidden = true
        panel:Hide()
    end

    if not panel.__MSUF_SettingsRegistered then
        local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        ns.MSUF_ColorsCategory = subcategory
        panel.__MSUF_SettingsRegistered = true
    end

    if panel.__MSUF_ColorsBuilt then
        return panel
    end

    if not panel.__MSUF_LazyBuildHooked then
        panel.__MSUF_LazyBuildHooked = true

        panel:HookScript("OnShow", function()
            if panel.__MSUF_ColorsBuilt or panel.__MSUF_ColorsBuilding then
                return
            end
            panel.__MSUF_ColorsBuilding = true

            -- Build immediately (no C_Timer.After(0)): avoids "needs second click" issues.
            ns.MSUF_RegisterColorsOptions_Full(parentCategory)

            panel.__MSUF_ColorsBuilding = nil
        end)
    end

    return panel
end
