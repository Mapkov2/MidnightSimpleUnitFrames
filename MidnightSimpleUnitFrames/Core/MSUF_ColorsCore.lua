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
local RunNextFrame          = _G.MSUF_RunNextFrame or _G.MSUF_Core_RunNextFrame or function(fn)
    if type(fn) ~= "function" then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, fn)
    else
        fn()
    end
end

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
-- Helper: apply visual updates (COALESCED)
-- Color picker drag can fire 30+ times/sec. Without coalescing,
-- each drag fires UpdateAllFonts + RefreshAllFrames + ... per tick.
-- We batch into a single C_Timer.After(0) flush.
------------------------------------------------------
local _pushPending = false
local function _RefreshAllBarBackgroundVisuals()
    local forEach = _G.MSUF_ForEachUnitFrame
    local applyBg = _G.MSUF_ApplyBarBackgroundVisual
    local refreshHP = _G.MSUF_UFCore_RefreshHealthBarColor
    if type(forEach) ~= "function" or type(applyBg) ~= "function" then return end

    forEach(function(frame)
        if frame and (frame.hpBarBG or frame.powerBarBG or frame.bg) then
            if type(refreshHP) == "function" and frame.hpBar then
                refreshHP(frame)
            end
            applyBg(frame)
        end
    end)
end

local function _PushVisualUpdates_Flush()
    -- PERF (4.22 Beta hotfix): pending flag stays TRUE during the entire
    -- flush body. The fallback path's pending dedup remains correct: any
    -- PushVisualUpdates() call during this flush is dropped, and the next
    -- one after we finish schedules normally. The primary path uses
    -- MSUF_ScheduleOnce and is unaffected. Cleared at END.
    --
    -- Same defense-in-depth pattern as _gfRosterFlush.
    _G.MSUF_ColorStyleRevision = (_G.MSUF_ColorStyleRevision or 0) + 1
    -- Invalidate settings cache so color tint fields (powerBgTint, barBgTint,
    -- aggro/dispel/purge, etc.) are re-read from DB before frames refresh.
    if _G.MSUF_UFCore_RefreshSettingsCache then
        _G.MSUF_UFCore_RefreshSettingsCache("COLOR_CHANGE")
    end
    _RefreshAllBarBackgroundVisuals()

    -- Rebuild the shared dispel color curve from the DB (per-type Magic /
    -- Curse / Disease / Poison / Bleed swatches from the Colors panel).
    -- Consumed by GF overlay, UF border highlight, and corner indicators —
    -- all of which pass curve output straight to C-side texture sinks.
    if ns and ns.GF and type(ns.GF.RebuildDispelColorCurve) == "function" then
        ns.GF.RebuildDispelColorCurve()
    end

    local fnFonts = _G.MSUF_UpdateAllFonts_Immediate or ns.MSUF_UpdateAllFonts or _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts
    if type(fnFonts) == "function" then
        fnFonts()
    end
    if _G.MSUF_RefreshAllIdentityColors then
        _G.MSUF_RefreshAllIdentityColors()
    end
    if _G.MSUF_RefreshAllPowerTextColors then
        _G.MSUF_RefreshAllPowerTextColors()
    end
    if ns.MSUF_ApplyGameplayVisuals then
        ns.MSUF_ApplyGameplayVisuals()
    end
    if ns.MSUF_RefreshAllFrames then
        ns.MSUF_RefreshAllFrames()
    elseif _G.MSUF_RefreshAllFrames then
        _G.MSUF_RefreshAllFrames()
    end
    -- Group Frames have their own render/dirty pipeline; refresh it explicitly
    -- so shared bar-color swatches (absorb/heal-absorb, borders, etc.) live-apply.
    do
        local gf = ns and ns.GF
        local refreshGFColors = (gf and gf.RefreshColors) or _G.MSUF_GF_RefreshColors
        if type(refreshGFColors) == "function" then
            refreshGFColors()
        end
    end

    -- Sync highlight priority stripe colors when border colors change.
    local reinit = _G.MSUF_PrioRows_Reinit
    if type(reinit) == "function" then reinit() end

    -- Live-update highlight border colors during test mode (zero cost when no test active).
    if _G.MSUF_BorderTestModesActive == true then
        local applyAll = _G.MSUF_ApplyBarOutlineThickness_All
        if type(applyAll) == "function" then applyAll() end
    end

    -- Safety: keep mouseover highlight bound to the correct unitframe.
    if ns.MSUF_ScheduleMouseoverHighlightFix then
        ns.MSUF_ScheduleMouseoverHighlightFix()
    elseif ns.MSUF_FixMouseoverHighlightBindings then
        ns.MSUF_FixMouseoverHighlightBindings()
    end

    -- Pending flag cleared at END (see header comment for rationale).
    _pushPending = false
end

local function PushVisualUpdates()
    local sched = _G.MSUF_ScheduleOnce
    if sched then
        sched("COLOR_PUSH_VISUALS", _PushVisualUpdates_Flush)
        return
    end

    -- Fallback for very early load before Foundation/MSUF_Scheduler.lua exports globals.
    if _pushPending then return end
    _pushPending = true
    RunNextFrame(_PushVisualUpdates_Flush)
end

------------------------------------------------------
-- Helper: ensure mouseover highlight border stays bound to its unitframe
-- (Prevents "floating highlight box" when the unitframe moves/hides.)
------------------------------------------------------
local function MSUF_GetHighlightObject(frame)
    if not frame then return nil end
    -- Mouseover highlight is UF-only here. Do not pick up generic
    -- `highlight` fields from edit-mode, menus, auras, or other helpers.
    if not (frame.unit and frame.hpBar and frame.highlightBorder) then return nil end
    return frame.highlightBorder
end

local function MSUF_GetHighlightRGB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hr, hg, hb = 1, 1, 1
    local hc = g.highlightColor
    if type(hc) == "table" then
        hr, hg, hb = hc[1] or 1, hc[2] or 1, hc[3] or 1
    else
        local key = (type(hc) == "string" and hc:lower()) or "white"
        local col = (type(MSUF_FONT_COLORS) == "table" and (MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white)) or nil
        if col then hr, hg, hb = col[1] or 1, col[2] or 1, col[3] or 1 end
    end
    return hr, hg, hb
end

local function MSUF_EnsureHoverLine(hb, key)
    local lines = hb._msufHoverLines
    if not lines then
        lines = {}
        hb._msufHoverLines = lines
    end
    local t = lines[key]
    if not t and hb.CreateTexture then
        t = hb:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        lines[key] = t
    end
    return t
end

local function MSUF_FixHighlightForFrame(frame)
    local hb = MSUF_GetHighlightObject(frame)
    if not hb then return end

    -- Ensure the highlight is parented to the unitframe (so it moves/hides with it)
    if hb.GetParent and hb.SetParent and hb:GetParent() ~= frame then
        hb:SetParent(frame)
    end

    -- Use an outside 4-line border. Backdrop edges are drawn partly inside the
    -- frame, which can put a horizontal line through HP/name text.
    if hb.SetBackdrop then hb:SetBackdrop(nil) end
    local edge = tonumber(hb._msufHoverEdgeSize) or 1
    if edge < 1 then edge = 1 end
    local r, g, b = MSUF_GetHighlightRGB()

    if hb.ClearAllPoints then
        hb:ClearAllPoints()
    end

    if _G.PixelUtil and _G.PixelUtil.SetPoint then
        _G.PixelUtil.SetPoint(hb, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        _G.PixelUtil.SetPoint(hb, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    elseif hb.SetPoint then
        hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        hb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end
    if hb.SetClipsChildren then hb:SetClipsChildren(false) end

    local top = MSUF_EnsureHoverLine(hb, "top")
    local bottom = MSUF_EnsureHoverLine(hb, "bottom")
    local left = MSUF_EnsureHoverLine(hb, "left")
    local right = MSUF_EnsureHoverLine(hb, "right")
    if top then
        top:ClearAllPoints()
        top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -edge, 0)
        top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", edge, 0)
        top:SetHeight(edge)
        top:SetVertexColor(r, g, b, 1)
        top:Show()
    end
    if bottom then
        bottom:ClearAllPoints()
        bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -edge, 0)
        bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", edge, 0)
        bottom:SetHeight(edge)
        bottom:SetVertexColor(r, g, b, 1)
        bottom:Show()
    end
    if left then
        left:ClearAllPoints()
        left:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, edge)
        left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, -edge)
        left:SetWidth(edge)
        left:SetVertexColor(r, g, b, 1)
        left:Show()
    end
    if right then
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, edge)
        right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, -edge)
        right:SetWidth(edge)
        right:SetVertexColor(r, g, b, 1)
        right:Show()
    end

    -- Keep it above bar fill, below user-facing text/icon layers where possible.
    if hb.SetFrameStrata and frame.GetFrameStrata then
        hb:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    end
    if hb.SetFrameLevel and frame.GetFrameLevel then
        local hp = frame.hpBar
        local baseLevel = (hp and hp.GetFrameLevel and hp:GetFrameLevel()) or (frame:GetFrameLevel() or 0)
        local wantLevel = baseLevel + 2
        local textFrame = frame.textFrame or frame.TextFrame
        local textLevel = textFrame and textFrame.GetFrameLevel and textFrame:GetFrameLevel()
        if textLevel and wantLevel >= textLevel then
            wantLevel = textLevel - 1
        end
        local frameLevel = frame:GetFrameLevel() or 0
        if wantLevel <= frameLevel then
            wantLevel = frameLevel + 1
        end
        hb:SetFrameLevel(wantLevel)
    end

    -- Safety: if the unitframe hides while hovered, also hide the highlight
    if not hb.MSUF_hideHooked and hooksecurefunc and frame.Hide then
        hb.MSUF_hideHooked = true
        local hideHighlight = hb.Hide
        local isHighlightShown = hb.IsShown
        hooksecurefunc(frame, "Hide", function()
            if hideHighlight and (not isHighlightShown or isHighlightShown(hb)) then
                hideHighlight(hb)
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
            local name = f.GetName and f:GetName()
            if type(name) == "string" and name:match("^MSUF_") then
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
                local name = v:GetName()
                if type(name) == "string" and name:match("^MSUF_") then
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
    local function _MouseoverHighlightFixFlush()
        if not (ns and ns.MSUF_FixMouseoverHighlightBindings) then return end

        ns.MSUF_FixMouseoverHighlightBindings()

        -- Mark done for this session. This scan is expensive (EnumerateFrames),
        -- and should not run again from PushVisualUpdates.
        ns._msufHoverFixDone = true
    end

    function ns.MSUF_ScheduleMouseoverHighlightFix()
        if ns and ns._msufHoverFixDone then return end

        local sched = _G.MSUF_ScheduleOnce
        if sched then
            sched("COLOR_MOUSEOVER_HIGHLIGHT_FIX", _MouseoverHighlightFixFlush)
        else
            RunNextFrame(_MouseoverHighlightFixFlush)
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


-- ═══════════════════════════════════════════════════════════════
-- Color Get/Set API — data-driven where possible, hand-written for complex logic
-- ═══════════════════════════════════════════════════════════════

-- Helper: simple RGB get from DB keys with defaults
local function _getRGB(rKey, gKey, bKey, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    return g[rKey] or defR, g[gKey] or defG, g[bKey] or defB
end

-- Helper: simple RGBA get from DB keys with defaults
local function _getRGBA(rKey, gKey, bKey, aKey, defR, defG, defB, defA)
    local g = _general()
    if not g then return defR, defG, defB, defA end
    return g[rKey] or defR, g[gKey] or defG, g[bKey] or defB, g[aKey] or defA
end

-- Helper: simple RGB set + PushVisualUpdates
local function _setRGB(rKey, gKey, bKey, r, g, b, defR, defG, defB)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR
    gen[gKey] = g or defG
    gen[bKey] = b or defB
    PushVisualUpdates()
end

-- Helper: simple RGBA set + PushVisualUpdates
local function _setRGBA(rKey, gKey, bKey, aKey, r, g, b, a, defR, defG, defB, defA)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR; gen[gKey] = g or defG; gen[bKey] = b or defB; gen[aKey] = a or defA
    PushVisualUpdates()
end

-- Helper: RGB get with palette fallback
local function _getRGBPalette(rKey, gKey, bKey, palKey, palDefault, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    if g[rKey] and g[gKey] and g[bKey] then return g[rKey], g[gKey], g[bKey] end
    local pal = g[palKey]
    if pal and MSUF_FONT_COLORS and MSUF_FONT_COLORS[pal] then
        local c = MSUF_FONT_COLORS[pal]; return c[1], c[2], c[3]
    end
    if palDefault and MSUF_FONT_COLORS and MSUF_FONT_COLORS[palDefault] then
        local c = MSUF_FONT_COLORS[palDefault]; return c[1], c[2], c[3]
    end
    return defR, defG, defB
end

-- Helper: RGB get with tonumber guards + palette fallback
local function _getRGBTonumber(rKey, gKey, bKey, palKey, palDefault, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    local r = tonumber(g[rKey])
    local gg = tonumber(g[gKey])
    local b = tonumber(g[bKey])
    if r and gg and b then return r, gg, b end
    if g[palKey] and MSUF_FONT_COLORS and MSUF_FONT_COLORS[g[palKey]] then
        local c = MSUF_FONT_COLORS[g[palKey]]; return c[1], c[2], c[3]
    end
    if palDefault and MSUF_FONT_COLORS and MSUF_FONT_COLORS[palDefault] then
        local c = MSUF_FONT_COLORS[palDefault]; return c[1], c[2], c[3]
    end
    return defR, defG, defB
end

-- ── Global Font Color ──
local function GetGlobalFontColor()
    local g = _general()
    if not g then return 1, 1, 1 end
    if g.useCustomFontColor and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    return 1, 1, 1
end
local function SetGlobalFontColor(r, g, b)
    local gen = _general(); if not gen then return end
    gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r or 1, g or 1, b or 1
    gen.useCustomFontColor = true; PushVisualUpdates()
end
local function ResetGlobalFontToPalette()
    local g = _general(); if not g then return end
    g.useCustomFontColor = false; g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB = nil, nil, nil
    PushVisualUpdates()
end

-- ── Castbar Text Color ──
local function GetCastbarTextColor()
    local g = _general()
    if not g then return GetGlobalFontColor() end
    if g.castbarFontR and g.castbarFontG and g.castbarFontB then return g.castbarFontR, g.castbarFontG, g.castbarFontB end
    return GetGlobalFontColor()
end
MSUF_GetCastbarTextColor = GetCastbarTextColor
local function SetCastbarTextColor(r, g, b)
    _setRGB("castbarFontR", "castbarFontG", "castbarFontB", r, g, b, 1, 1, 1)
end
local function ResetCastbarTextColorToGlobal()
    local g = _general(); if not g then return end
    g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil; PushVisualUpdates()
end

-- ── Castbar Border Color ──
local function GetCastbarBorderColor() return _getRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", 0, 0, 0, 1) end
local function SetCastbarBorderColor(r, g, b, a) _setRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", r, g, b, a, 0, 0, 0, 1) end
local function ResetCastbarBorderColor()
    local g = _general(); if not g then return end
    g.castbarBorderR, g.castbarBorderG, g.castbarBorderB, g.castbarBorderA = nil, nil, nil, nil; PushVisualUpdates()
end

-- ── Castbar Background Color ──
local function GetCastbarBackgroundColor()
    local g = _general()
    if not g then return 0.10, 0.10, 0.10, 0.85 end
    return tonumber(g.castbarBgR) or 0.10, tonumber(g.castbarBgG) or 0.10, tonumber(g.castbarBgB) or 0.10, tonumber(g.castbarBgA) or 0.85
end
_G.MSUF_GetCastbarBackgroundColor = GetCastbarBackgroundColor
local function SetCastbarBackgroundColor(r, g, b, a) _setRGBA("castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA", r, g, b, a, 0.10, 0.10, 0.10, 0.85) end
local function ResetCastbarBackgroundColor()
    local g = _general(); if not g then return end
    g.castbarBgR, g.castbarBgG, g.castbarBgB, g.castbarBgA = nil, nil, nil, nil; PushVisualUpdates()
end

-- ── Cast Colors (interruptible / non-interruptible / feedback) ──
local function GetInterruptibleCastColor() return _getRGBPalette("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", "castbarInterruptibleColor", "turquoise", 0, 0.9, 0.8) end
MSUF_GetInterruptibleCastColor = GetInterruptibleCastColor
local function SetInterruptibleCastColor(r, g, b) _setRGB("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", r, g, b, 0, 0.9, 0.8) end
local function GetNonInterruptibleCastColor() return _getRGBTonumber("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", "castbarNonInterruptibleColor", "red", 0.4, 0.01, 0.01) end
MSUF_GetNonInterruptibleCastColor = GetNonInterruptibleCastColor
local function SetNonInterruptibleCastColor(r, g, b) _setRGB("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", r, g, b, 0.4, 0.01, 0.01) end
local function GetInterruptFeedbackCastColor() return _getRGBTonumber("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", "castbarInterruptFeedbackColor", "yellow", 1.0, 0.82, 0.0) end
local function SetInterruptFeedbackCastColor(r, g, b) _setRGB("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", r, g, b, 1.0, 0.82, 0.0) end

-- ── Player Castbar Override ──
local function GetPlayerCastbarOverrideEnabled() return (_general() or {}).playerCastbarOverrideEnabled and true or false end
local function SetPlayerCastbarOverrideEnabled(enabled)
    local g = _general(); if not g then return end; g.playerCastbarOverrideEnabled = enabled and true or false; PushVisualUpdates()
end
local function GetPlayerCastbarOverrideMode() return (_general() or {}).playerCastbarOverrideMode or "COLOR" end
local function SetPlayerCastbarOverrideMode(mode)
    local g = _general(); if not g then return end; g.playerCastbarOverrideMode = mode; PushVisualUpdates()
end
local function GetPlayerCastbarOverrideColor() return _getRGB("playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB", 0.0, 0.6, 1.0) end
local function SetPlayerCastbarOverrideColor(r, g, b) _setRGB("playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB", r, g, b, 0.0, 0.6, 1.0) end

-- ── Class Colors ──
local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local function GetClassColor(token)
    local db = _G.MSUF_DB
    if db and db.classColors and db.classColors[token] then
        local t = db.classColors[token]
        return t.r or 1, t.g or 1, t.b or 1
    end
    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if rc then return rc.r, rc.g, rc.b end
    return 1, 1, 1
end
local function SetClassColor(token, r, g, b)
    local db = _G.MSUF_DB; if not db then return end
    db.classColors = db.classColors or {}
    db.classColors[token] = { r = r or 1, g = g or 1, b = b or 1 }
    PushVisualUpdates()
end
local function ResetAllClassColors()
    if _G.MSUF_DB then _G.MSUF_DB.classColors = nil end; PushVisualUpdates()
end

-- ── Class Bar Background Color ──
local function GetClassBarBgColor() return _getRGB("classBarBgR", "classBarBgG", "classBarBgB", 0, 0, 0) end
local function SetClassBarBgColor(r, g, b) _setRGB("classBarBgR", "classBarBgG", "classBarBgB", r, g, b, 0, 0, 0) end
local function ResetClassBarBgColor()
    local g = _general(); if not g then return end
    g.classBarBgR, g.classBarBgG, g.classBarBgB = nil, nil, nil; PushVisualUpdates()
end

-- ── Bar BG Match HP ──
local function GetBarBgMatchHP() return (_general() or {}).barBgMatchHPColor and true or false end
local function SetBarBgMatchHP(v)
    local g = _general()
    if g then
        g.barBgMatchHPColor = v and true or false
        if v then g.barBgClassColor = false end
        PushVisualUpdates()
    end
end
local function GetBarBgClassColor() return (_general() or {}).barBgClassColor and true or false end
local function SetBarBgClassColor(v)
    local g = _general()
    if g then
        g.barBgClassColor = v and true or false
        if v then g.barBgMatchHPColor = false end
        PushVisualUpdates()
    end
end

-- ── NPC Colors ──
local NPC_TYPE_KEYS = { "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }
local NPC_TYPE_UNITS = { { key = "npcTypeTarget", label = "Target" }, { key = "npcTypeFocus", label = "Focus" }, { key = "npcTypeBoss", label = "Boss" }, { key = "npcTypeToT", label = "Target of Target" } }

local function GetNPCColor(kind)
    local db = _G.MSUF_DB
    if db and db.npcColors and db.npcColors[kind] then
        local t = db.npcColors[kind]; return t.r or 0, t.g or 1, t.b or 0
    end
    local def = { friendly={0,1,0}, neutral={1,1,0}, enemy={0.85,0.10,0.10}, dead={0.4,0.4,0.4},
        npcBoss={0.74,0.11,0}, npcMiniboss={0.56,0,0.74}, npcCaster={0,0.45,0.74}, npcMelee={0.99,0.99,0.99}, npcRegular={0.70,0.56,0.33} }
    local d = def[kind] or def.enemy; return d[1], d[2], d[3]
end
local function SetNPCColor(kind, r, g, b)
    local db = _G.MSUF_DB; if not db then return end
    db.npcColors = db.npcColors or {}
    db.npcColors[kind] = { r = r or 0, g = g or 1, b = b or 0 }
    PushVisualUpdates()
end
local function ResetAllNPCColors() if _G.MSUF_DB then _G.MSUF_DB.npcColors = nil end; PushVisualUpdates() end
local function GetNPCColorMode() return (_general() or {}).npcColorMode or "reaction" end
local function SetNPCColorMode(mode) local g = _general(); if g then g.npcColorMode = mode; PushVisualUpdates() end end
local function GetNPCTypeColorBar() local g = _general(); return not g or g.npcTypeColorBar ~= false end
local function SetNPCTypeColorBar(v) local g = _general(); if g then g.npcTypeColorBar = v and true or false; PushVisualUpdates() end end
local function GetNPCTypeColorText() local g = _general(); return not g or g.npcTypeColorText ~= false end
local function SetNPCTypeColorText(v) local g = _general(); if g then g.npcTypeColorText = v and true or false; PushVisualUpdates() end end
local function ResetNPCTypeColors() if _G.MSUF_DB then _G.MSUF_DB.npcColors = nil end; PushVisualUpdates() end
local function GetNPCTypePerUnit(key) local g = _general(); return not g or g[key] ~= false end
local function SetNPCTypePerUnit(key, v) local g = _general(); if g then g[key] = v and true or false; PushVisualUpdates() end end

-- ── Pet Frame Color ──
local function GetPetFrameColor() return _getRGB("petFrameColorR", "petFrameColorG", "petFrameColorB", 0, 0.8, 0) end
local function SetPetFrameColor(r, g, b) _setRGB("petFrameColorR", "petFrameColorG", "petFrameColorB", r, g, b, 0, 0.8, 0) end

-- ── Absorb / Heal-Absorb Overlay Colors ──
-- Keys aligned with the readers used by main UF, GF Render, GF Core preview,
-- GF AuraPreview, and the bar-color reset in Options_Colors. The picker used
-- to write `absorbColor*` / `healAbsorbColor*` while every reader consumed
-- `absorbBarColor*` / `healAbsorbBarColor*` — so color changes never landed.
-- One-time migration of the legacy keys is done in MSUF_Defaults.
local function GetAbsorbOverlayColor()         return _getRGBA("absorbBarColorR",     "absorbBarColorG",     "absorbBarColorB",     "absorbBarColorA",     1.0, 1.0, 1.0, 0.45) end
local function SetAbsorbOverlayColor(r, g, b, a)      _setRGBA("absorbBarColorR",     "absorbBarColorG",     "absorbBarColorB",     "absorbBarColorA",     r, g, b, a, 1.0, 1.0, 1.0, 0.45) end
local function GetHealAbsorbOverlayColor()     return _getRGBA("healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA", 0.7, 0.0, 0.0, 0.45) end
local function SetHealAbsorbOverlayColor(r, g, b, a)  _setRGBA("healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA", r, g, b, a, 0.7, 0.0, 0.0, 0.45) end

-- ── Power Bar Background ──
local function GetPowerBarBackgroundColor()
    local g = _general()
    if not g then return 0, 0, 0 end
    return tonumber(g.powerBarBgColorR) or 0, tonumber(g.powerBarBgColorG) or 0, tonumber(g.powerBarBgColorB) or 0
end
local function SetPowerBarBackgroundColor(r, g, b) _setRGB("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", r, g, b, 0, 0, 0) end
local function GetPowerBarBackgroundMatchHP() return (_general() or {}).powerBarBgMatchBarColor and true or false end
local function SetPowerBarBackgroundMatchHP(v) local g = _general(); if g then g.powerBarBgMatchBarColor = v and true or false; PushVisualUpdates() end end

-- ── Aggro Border ──
local function GetAggroBorderColor() return _getRGB("aggroBorderR", "aggroBorderG", "aggroBorderB", 1.0, 0.5, 0.0) end
local function SetAggroBorderColor(r, g, b) _setRGB("aggroBorderR", "aggroBorderG", "aggroBorderB", r, g, b, 1.0, 0.5, 0.0) end

-- ═══════════════════════════════════════════════════════════════
-- Export table
-- ═══════════════════════════════════════════════════════════════
ns._colorsAPI = {
    PushVisualUpdates               = PushVisualUpdates,
    GetGlobalFontColor              = GetGlobalFontColor,
    SetGlobalFontColor              = SetGlobalFontColor,
    ResetGlobalFontToPalette        = ResetGlobalFontToPalette,
    GetCastbarTextColor             = GetCastbarTextColor,
    SetCastbarTextColor             = SetCastbarTextColor,
    ResetCastbarTextColorToGlobal   = ResetCastbarTextColorToGlobal,
    GetCastbarBorderColor           = GetCastbarBorderColor,
    SetCastbarBorderColor           = SetCastbarBorderColor,
    ResetCastbarBorderColor         = ResetCastbarBorderColor,
    GetCastbarBackgroundColor       = GetCastbarBackgroundColor,
    SetCastbarBackgroundColor       = SetCastbarBackgroundColor,
    ResetCastbarBackgroundColor     = ResetCastbarBackgroundColor,
    GetInterruptibleCastColor       = GetInterruptibleCastColor,
    SetInterruptibleCastColor       = SetInterruptibleCastColor,
    GetNonInterruptibleCastColor    = GetNonInterruptibleCastColor,
    SetNonInterruptibleCastColor    = SetNonInterruptibleCastColor,
    GetInterruptFeedbackCastColor   = GetInterruptFeedbackCastColor,
    SetInterruptFeedbackCastColor   = SetInterruptFeedbackCastColor,
    GetPlayerCastbarOverrideEnabled = GetPlayerCastbarOverrideEnabled,
    SetPlayerCastbarOverrideEnabled = SetPlayerCastbarOverrideEnabled,
    GetPlayerCastbarOverrideMode    = GetPlayerCastbarOverrideMode,
    SetPlayerCastbarOverrideMode    = SetPlayerCastbarOverrideMode,
    GetPlayerCastbarOverrideColor   = GetPlayerCastbarOverrideColor,
    SetPlayerCastbarOverrideColor   = SetPlayerCastbarOverrideColor,
    GetClassColor                   = GetClassColor,
    SetClassColor                   = SetClassColor,
    ResetAllClassColors             = ResetAllClassColors,
    CLASS_TOKENS                    = CLASS_TOKENS,
    GetClassBarBgColor              = GetClassBarBgColor,
    SetClassBarBgColor              = SetClassBarBgColor,
    ResetClassBarBgColor            = ResetClassBarBgColor,
    GetBarBgMatchHP                 = GetBarBgMatchHP,
    SetBarBgMatchHP                 = SetBarBgMatchHP,
    GetBarBgClassColor              = GetBarBgClassColor,
    SetBarBgClassColor              = SetBarBgClassColor,
    GetNPCColor                     = GetNPCColor,
    SetNPCColor                     = SetNPCColor,
    ResetAllNPCColors               = ResetAllNPCColors,
    GetNPCColorMode                 = GetNPCColorMode,
    SetNPCColorMode                 = SetNPCColorMode,
    GetNPCTypeColorBar              = GetNPCTypeColorBar,
    SetNPCTypeColorBar              = SetNPCTypeColorBar,
    GetNPCTypeColorText             = GetNPCTypeColorText,
    SetNPCTypeColorText             = SetNPCTypeColorText,
    ResetNPCTypeColors              = ResetNPCTypeColors,
    NPC_TYPE_KEYS                   = NPC_TYPE_KEYS,
    NPC_TYPE_UNITS                  = NPC_TYPE_UNITS,
    GetNPCTypePerUnit               = GetNPCTypePerUnit,
    SetNPCTypePerUnit               = SetNPCTypePerUnit,
    GetPetFrameColor                = GetPetFrameColor,
    SetPetFrameColor                = SetPetFrameColor,
    GetAbsorbOverlayColor           = GetAbsorbOverlayColor,
    SetAbsorbOverlayColor           = SetAbsorbOverlayColor,
    GetHealAbsorbOverlayColor       = GetHealAbsorbOverlayColor,
    SetHealAbsorbOverlayColor       = SetHealAbsorbOverlayColor,
    GetPowerBarBackgroundColor      = GetPowerBarBackgroundColor,
    SetPowerBarBackgroundColor      = SetPowerBarBackgroundColor,
    GetAggroBorderColor             = GetAggroBorderColor,
    SetAggroBorderColor             = SetAggroBorderColor,
    GetPowerBarBackgroundMatchHP    = GetPowerBarBackgroundMatchHP,
    SetPowerBarBackgroundMatchHP    = SetPowerBarBackgroundMatchHP,
}
