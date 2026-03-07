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
local type                  = type
local tonumber              = tonumber

------------------------------------------------------
-- P0 perf: Cached DB resolver.
-- After PLAYER_LOGIN, EnsureDB() is a no-op and MSUF_DB.general
-- always exists.  Every getter was paying for:
--   1× global lookup (EnsureDB), 1× function call, 1× "or {}" guard
-- ~20 getters × N calls/sec = thousands of redundant ops.
--
-- _general() caches the ref and only refreshes when MSUF_DB identity
-- changes (profile switch replaces the entire table).
------------------------------------------------------
local _cachedDB, _cachedGen

local function _general()
    local db = MSUF_DB
    if db and _cachedDB == db then
        return _cachedGen
    end
    -- First call or profile switch: resolve fresh.
    if EnsureDB then EnsureDB() end
    db = MSUF_DB
    if not db then return nil end
    db.general = db.general or {}
    _cachedDB  = db
    _cachedGen = db.general
    return _cachedGen
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
    local g = _general()
    if not g then return 1, 1, 1 end

    if g.useCustomFontColor
       and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB
    then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end

    return 1, 1, 1
end

local function SetGlobalFontColor(r, g, b)
    local gen = _general()
    if not gen then return end

    gen.fontColorCustomR = r or 1
    gen.fontColorCustomG = g or 1
    gen.fontColorCustomB = b or 1
    gen.useCustomFontColor = true

    PushVisualUpdates()
end

local function ResetGlobalFontToPalette()
    local g = _general()
    if not g then return end

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
    local g = _general()
    if not g then return GetGlobalFontColor() end

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
    local gen = _general()
    if not gen then return end

    gen.castbarTextR = r or 1
    gen.castbarTextG = g or 1
    gen.castbarTextB = b or 1
    gen.castbarTextUseCustom = true

    PushVisualUpdates()
end

local function ResetCastbarTextColorToGlobal()
    local g = _general()
    if not g then return end

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
    local g = _general()
    if not g then return 0, 0, 0, 1 end

    local r  = tonumber(g.castbarBorderR); if r  == nil then r  = 0 end
    local gg = tonumber(g.castbarBorderG); if gg == nil then gg = 0 end
    local b  = tonumber(g.castbarBorderB); if b  == nil then b  = 0 end
    local a  = tonumber(g.castbarBorderA); if a  == nil then a  = 1 end
    return r, gg, b, a
end

local function SetCastbarBorderColor(r, g, b, a)
    local gen = _general()
    if not gen then return end

    gen.castbarBorderR = r
    gen.castbarBorderG = g
    gen.castbarBorderB = b
    gen.castbarBorderA = a or 1

    if _G.MSUF_ApplyCastbarOutlineToAll then
        _G.MSUF_ApplyCastbarOutlineToAll(true)
    end
end

local function ResetCastbarBorderColor()
    local g = _general()
    if not g then return end

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
    local g = _general()
    if not g then return 0.176, 0.176, 0.176, 1 end

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
    local gen = _general()
    if not gen then return end

    gen.castbarBgR = r
    gen.castbarBgG = g
    gen.castbarBgB = b
    gen.castbarBgA = a or 1

    -- Live-apply to all active castbar frames (same pattern as SetCastbarBorderColor)
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
end

local function ResetCastbarBackgroundColor()
    local g = _general()
    if not g then return end

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
    local g = _general()
    if not g then return 0, 0.9, 0.8 end

    if g.castbarInterruptibleR and g.castbarInterruptibleG and g.castbarInterruptibleB then
        return g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB
    end

    if g.castbarInterruptibleColor and MSUF_FONT_COLORS and MSUF_FONT_COLORS[g.castbarInterruptibleColor] then
        local c = MSUF_FONT_COLORS[g.castbarInterruptibleColor]
        return c[1], c[2], c[3]
    end

    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["turquoise"] then
        local c = MSUF_FONT_COLORS["turquoise"]
        return c[1], c[2], c[3]
    end

    return 0, 0.9, 0.8
end
MSUF_GetInterruptibleCastColor = GetInterruptibleCastColor

local function SetInterruptibleCastColor(r, g, b)
    local gen = _general()
    if not gen then return end

    gen.castbarInterruptibleR = r or 0
    gen.castbarInterruptibleG = g or 0.9
    gen.castbarInterruptibleB = b or 0.8

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Non-interruptible cast color
------------------------------------------------------
local function GetNonInterruptibleCastColor()
    local g = _general()
    if not g then return 0.4, 0.01, 0.01 end

    local r = tonumber(g.castbarNonInterruptibleR)
    local gg = tonumber(g.castbarNonInterruptibleG)
    local b = tonumber(g.castbarNonInterruptibleB)

    if r and gg and b then
        return r, gg, b
    end

    if g.castbarNonInterruptibleColor
        and MSUF_FONT_COLORS
        and MSUF_FONT_COLORS[g.castbarNonInterruptibleColor]
    then
        local c = MSUF_FONT_COLORS[g.castbarNonInterruptibleColor]
        return c[1], c[2], c[3]
    end

    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["red"] then
        local c = MSUF_FONT_COLORS["red"]
        return c[1], c[2], c[3]
    end

    return 0.4, 0.01, 0.01
end

MSUF_GetNonInterruptibleCastColor = GetNonInterruptibleCastColor

local function SetNonInterruptibleCastColor(r, g, b)
    local gen = _general()
    if not gen then return end

    gen.castbarNonInterruptibleR = r or 0.4
    gen.castbarNonInterruptibleG = g or 0.01
    gen.castbarNonInterruptibleB = b or 0.01

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Interrupt feedback color
------------------------------------------------------
local function GetInterruptFeedbackCastColor()
    local g = _general()
    if not g then return 0.8, 0.1, 0.1 end

    local r  = tonumber(g.castbarInterruptR)
    local gg = tonumber(g.castbarInterruptG)
    local b  = tonumber(g.castbarInterruptB)

    if r and gg and b then
        return r, gg, b
    end

    if g.castbarInterruptColor
        and MSUF_FONT_COLORS
        and MSUF_FONT_COLORS[g.castbarInterruptColor]
    then
        local c = MSUF_FONT_COLORS[g.castbarInterruptColor]
        return c[1], c[2], c[3]
    end

    if MSUF_FONT_COLORS and MSUF_FONT_COLORS["red"] then
        local c = MSUF_FONT_COLORS["red"]
        return c[1], c[2], c[3]
    end

    return 0.8, 0.1, 0.1
end

local function SetInterruptFeedbackCastColor(r, g, b)
    local gen = _general()
    if not gen then return end

    gen.castbarInterruptR = r or 0.8
    gen.castbarInterruptG = g or 0.1
    gen.castbarInterruptB = b or 0.1

    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Player castbar override
------------------------------------------------------
local function GetPlayerCastbarOverrideEnabled()
    local g = _general()
    return g and g.playerCastbarOverrideEnabled == true or false
end

local function SetPlayerCastbarOverrideEnabled(enabled)
    local g = _general()
    if not g then return end
    g.playerCastbarOverrideEnabled = (enabled == true)
    PushVisualUpdates()
end

local function GetPlayerCastbarOverrideMode()
    local g = _general()
    if not g then return "CLASS" end
    local m = g.playerCastbarOverrideMode
    if m == "CUSTOM" or m == "CLASS" then return m end
    return "CLASS"
end

local function SetPlayerCastbarOverrideMode(mode)
    local g = _general()
    if not g then return end
    g.playerCastbarOverrideMode = (mode == "CUSTOM") and "CUSTOM" or "CLASS"
    PushVisualUpdates()
end

local function GetPlayerCastbarOverrideColor()
    local g = _general()
    if not g then return 1, 1, 1 end
    local r = tonumber(g.playerCastbarOverrideR) or 1
    local gg = tonumber(g.playerCastbarOverrideG) or 1
    local b = tonumber(g.playerCastbarOverrideB) or 1
    return r, gg, b
end

local function SetPlayerCastbarOverrideColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.playerCastbarOverrideR = r or 1
    gen.playerCastbarOverrideG = g or 1
    gen.playerCastbarOverrideB = b or 1
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
    local db = MSUF_DB
    if db then
        local cc = db.classColors
        local t = cc and cc[token]
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
    local gen = _general()
    if not gen then return end

    local db = MSUF_DB
    db.classColors = db.classColors or {}
    local t = db.classColors[token] or {}
    t.r, t.g, t.b = r or 1, g or 1, b or 1
    db.classColors[token] = t

    PushVisualUpdates()
end

local function ResetAllClassColors()
    if not MSUF_DB then return end
    MSUF_DB.classColors = nil
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Class Color bar background
------------------------------------------------------
local function GetClassBarBgColor()
    local g = _general()
    if not g then return 0, 0, 0 end

    local r  = tonumber(g.classBarBgR) or 0
    local gg = tonumber(g.classBarBgG) or 0
    local b  = tonumber(g.classBarBgB) or 0

    if r  < 0 then r  = 0 elseif r  > 1 then r  = 1 end
    if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
    if b  < 0 then b  = 0 elseif b  > 1 then b  = 1 end

    return r, gg, b
end

local function SetClassBarBgColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.classBarBgR = r or 0
    gen.classBarBgG = g or 0
    gen.classBarBgB = b or 0
    PushVisualUpdates()
end

local function ResetClassBarBgColor()
    SetClassBarBgColor(0, 0, 0)
end


------------------------------------------------------
-- Helpers: Bar background match HP color
------------------------------------------------------
local function GetBarBgMatchHP()
    local g = _general()
    return g and g.barBgMatchHPColor and true or false
end

local function SetBarBgMatchHP(v)
    local g = _general()
    if not g then return end
    g.barBgMatchHPColor = v and true or false
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: NPC reaction colors
-- P2 perf: lookup table eliminates if/elseif chain.
------------------------------------------------------
local NPC_DEFAULT_COLORS = {
    friendly = { 0, 1, 0 },
    neutral  = { 1, 1, 0 },
    enemy    = { 1, 0, 0 },
    dead     = { 0.4, 0.4, 0.4 },
}
local NPC_FALLBACK = { 1, 1, 1 }

local function GetNPCColor(kind)
    local def = NPC_DEFAULT_COLORS[kind] or NPC_FALLBACK

    local db = MSUF_DB
    if db then
        local nc = db.npcColors
        local t = nc and nc[kind]
        if t and t.r and t.g and t.b then
            return t.r, t.g, t.b
        end
    end

    return def[1], def[2], def[3]
end

local function SetNPCColor(kind, r, g, b)
    local gen = _general()
    if not gen then return end

    local db = MSUF_DB
    db.npcColors = db.npcColors or {}
    local t = db.npcColors[kind] or {}
    t.r = r or 1
    t.g = g or 1
    t.b = b or 1
    db.npcColors[kind] = t

    PushVisualUpdates()
end

local function ResetAllNPCColors()
    if not MSUF_DB then return end
    MSUF_DB.npcColors = nil
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Pet frame bar color
------------------------------------------------------
local function GetPetFrameColor()
    local g = _general()
    if not g then return 0, 1, 0 end

    local r = g.petFrameColorR
    local gg = g.petFrameColorG
    local b = g.petFrameColorB

    if type(r) ~= "number" or type(gg) ~= "number" or type(b) ~= "number" then
        return 0, 1, 0
    end

    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end

    return r, gg, b
end

local function SetPetFrameColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.petFrameColorR = r
    gen.petFrameColorG = g
    gen.petFrameColorB = b
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Absorb / Heal-Absorb overlay colors
------------------------------------------------------
local function GetAbsorbOverlayColor()
    local g = _general()
    if g then
        local ar, ag, ab = g.absorbBarColorR, g.absorbBarColorG, g.absorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            return ar, ag, ab
        end
    end
    return 0.8, 0.9, 1.0
end

local function SetAbsorbOverlayColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.absorbBarColorR = r
    gen.absorbBarColorG = g
    gen.absorbBarColorB = b
    PushVisualUpdates()
end

local function GetHealAbsorbOverlayColor()
    local g = _general()
    if g then
        local ar, ag, ab = g.healAbsorbBarColorR, g.healAbsorbBarColorG, g.healAbsorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            return ar, ag, ab
        end
    end
    return 1.0, 0.4, 0.4
end

local function SetHealAbsorbOverlayColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.healAbsorbBarColorR = r
    gen.healAbsorbBarColorG = g
    gen.healAbsorbBarColorB = b
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Power bar background color
------------------------------------------------------
local function GetPowerBarBackgroundColor()
    local g = _general()
    if not g then return 0, 0, 0 end

    -- Check explicit power bar BG override first
    local r = g.powerBarBgColorR
    local gg = g.powerBarBgColorG
    local b = g.powerBarBgColorB

    if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
        if r < 0 then r = 0 elseif r > 1 then r = 1 end
        if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
        if b < 0 then b = 0 elseif b > 1 then b = 1 end
        return r, gg, b
    end

    -- Fallback: mirror bar background tint
    local defR = tonumber(g.classBarBgR) or 0
    local defG = tonumber(g.classBarBgG) or 0
    local defB = tonumber(g.classBarBgB) or 0

    if defR < 0 then defR = 0 elseif defR > 1 then defR = 1 end
    if defG < 0 then defG = 0 elseif defG > 1 then defG = 1 end
    if defB < 0 then defB = 0 elseif defB > 1 then defB = 1 end

    return defR, defG, defB
end

local function SetPowerBarBackgroundColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.powerBarBgColorR = r
    gen.powerBarBgColorG = g
    gen.powerBarBgColorB = b
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Aggro border color
------------------------------------------------------
local function GetAggroBorderColor()
    local g = _general()
    if g then
        local r = g.aggroBorderColorR
        local gg = g.aggroBorderColorG
        local b = g.aggroBorderColorB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 1, 0.50, 0
end

local function SetAggroBorderColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.aggroBorderColorR = r
    gen.aggroBorderColorG = g
    gen.aggroBorderColorB = b
    PushVisualUpdates()
end


------------------------------------------------------
-- Helpers: Power bar background match HP
------------------------------------------------------
local function GetPowerBarBackgroundMatchHP()
    local g = _general()
    if g then
        local v = g.powerBarBgMatchHPColor
        if v ~= nil then
            return v and true or false
        end
    end
    -- Legacy fallback
    local db = MSUF_DB
    if db and db.bars then
        return db.bars.powerBarBgMatchBarColor and true or false
    end
    return false
end

local function SetPowerBarBackgroundMatchHP(enabled)
    local g = _general()
    if not g then return end

    local db = MSUF_DB
    db.bars = db.bars or {}

    local v = enabled and true or false
    g.powerBarBgMatchHPColor = v
    db.bars.powerBarBgMatchBarColor = v

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
