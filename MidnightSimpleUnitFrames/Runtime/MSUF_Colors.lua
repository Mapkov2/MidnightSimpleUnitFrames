--- MSUF_ColorsCore.lua
--- Runtime color logic: Get/Set/Reset for all color categories,
--- PushVisualUpdates, and mouseover-highlight system.
--- Loaded early (before Gameplay, Castbars, Borders etc.) so hot-path
--- consumers can call the getters at zero extra lookup cost.
--- The Options panel lives in MSUF_Options_Colors.lua.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF
MSUF.Public = MSUF.Public or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

---
--- Local shortcuts (core only - no UI-framework refs)
---
local EnsureDB              = _G.MSUF_EnsureDB
local RAID_CLASS_COLORS     = RAID_CLASS_COLORS
local C_Timer               = C_Timer
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

---
--- P0 perf: Cached DB resolver.
--- After PLAYER_LOGIN, EnsureDB() is a no-op and MSUF_DB.general
--- always exists. Every getter was paying for:
--- 1- global lookup (EnsureDB), 1- function call, 1- "or {}" guard
--- ~20 getters - N calls/sec = thousands of redundant ops.
---
--- _general() caches the ref and only refreshes when MSUF_DB identity
--- changes (profile switch replaces the entire table).
---
local _cachedDB, _cachedGen

local function _general()
    local db = MSUF_DB
    if db and _cachedDB == db then
        return _cachedGen
    end
    --- First call or profile switch: resolve fresh.
    if EnsureDB then EnsureDB() end
    db = MSUF_DB
    if not db then return nil end
    db.general = db.general or {}
    _cachedDB  = db
    _cachedGen = db.general
    return _cachedGen
end

---
--- Helper: apply visual updates (COALESCED)
--- Color picker drag can fire 30+ times/sec. Without coalescing,
--- each drag fires UpdateAllFonts + RefreshAllFrames + ... per tick.
--- We batch into a single C_Timer.After(0) flush.
---
local _pushPending = false
local function _RefreshAllBarBackgroundVisuals()
    local applyBg = _G.MSUF_ApplyBarBackgroundVisual
    local refreshHP = _G.MSUF_UFCore_RefreshHealthBarColor
    local syncMissing = _G.MSUF_Alpha_UpdatePreserveMissingHP
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" or type(applyBg) ~= "function" then return end

    for _, frame in pairs(frames) do
        if frame and (frame.hpBarBG or frame.powerBarBG or frame.bg) then
            if type(refreshHP) == "function" and frame.hpBar then
                refreshHP(frame)
            end
            applyBg(frame)
            if type(syncMissing) == "function" then
                syncMissing(frame)
            end
        end
    end
end

local function _PushVisualUpdates_Flush()
    --- PERF (4.22 Beta hotfix): pending flag stays TRUE during the entire
    --- flush body. The fallback path's pending dedup remains correct: any
    --- PushVisualUpdates() call during this flush is dropped, and the next
    --- one after we finish schedules normally. The primary path uses
    --- MSUF_ScheduleOnce and is unaffected. Cleared at END.
    ---
    --- Same defense-in-depth pattern as _gfRosterFlush.
    ExportPublic("MSUF_ColorStyleRevision", (_G.MSUF_ColorStyleRevision or 0) + 1)
    --- Invalidate settings cache so color tint fields (powerBgTint, barBgTint,
    --- aggro/dispel/purge, etc.) are re-read from DB before frames refresh.
    if _G.MSUF_UFCore_RefreshSettingsCache then
        _G.MSUF_UFCore_RefreshSettingsCache("COLOR_CHANGE")
    end
    _RefreshAllBarBackgroundVisuals()

    --- Rebuild the shared dispel color curve from the DB (per-type Magic /
    --- Curse / Disease / Poison / Bleed swatches from the Colors panel).
    --- Consumed by GF overlay, UF border highlight, and corner indicators -
    --- all of which pass curve output straight to C-side texture sinks.
    if MSUF and MSUF.GF and type(MSUF.GF.RebuildDispelColorCurve) == "function" then
        MSUF.GF.RebuildDispelColorCurve()
    end

    local fnFonts = _G.MSUF_UpdateAllFonts_Immediate or MSUF.MSUF_UpdateAllFonts or _G.MSUF_UpdateAllFonts
    if type(fnFonts) == "function" then
        fnFonts()
    end
    if _G.MSUF_RefreshAllIdentityColors then
        _G.MSUF_RefreshAllIdentityColors()
    end
    if _G.MSUF_RefreshAllPowerTextColors then
        _G.MSUF_RefreshAllPowerTextColors()
    end
    if MSUF.MSUF_ApplyGameplayVisuals then
        MSUF.MSUF_ApplyGameplayVisuals()
    end
    if MSUF.MSUF_RefreshAllFrames then
        MSUF.MSUF_RefreshAllFrames()
    elseif _G.MSUF_RefreshAllFrames then
        _G.MSUF_RefreshAllFrames()
    end
    --- Group Frames have their own render/dirty pipeline; refresh it explicitly
    --- so shared bar-color swatches (absorb/heal-absorb, borders, etc.) live-apply.
    do
        local gf = MSUF and MSUF.GF
        local refreshGFColors = (gf and gf.RefreshColors) or _G.MSUF_GF_RefreshColors
        if type(refreshGFColors) == "function" then
            refreshGFColors()
        end
    end

    --- Sync highlight priority stripe colors when border colors change.
    local reinit = _G.MSUF_PrioRows_Reinit
    if type(reinit) == "function" then reinit() end

    --- Live-update static bar outlines and highlight test border colors.
    do
        local applyAll = _G.MSUF_ApplyBarOutlineThickness_All
        if type(applyAll) == "function" then applyAll() end
    end
    if type(_G.MSUF_ApplyRoundedUnitframes) == "function" then
        _G.MSUF_ApplyRoundedUnitframes()
    end
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh("MSUF_COLOR_CHANGE")
    end

    --- Repaint the mouseover highlight cache so colour/size edits apply live.
    if _G.MSUF_RefreshMouseoverHighlight then
        _G.MSUF_RefreshMouseoverHighlight()
    end

    --- Pending flag cleared at END (see header comment for rationale).
    _pushPending = false
end

local function PushVisualUpdates()
    local sched = _G.MSUF_ScheduleOnce
    if sched then
        sched("COLOR_PUSH_VISUALS", _PushVisualUpdates_Flush)
        return
    end

    --- Fallback for very early load before Kernel/MSUF_Scheduler.lua exports globals.
    if _pushPending then return end
    _pushPending = true
    RunNextFrame(_PushVisualUpdates_Flush)
end

--- ---------------------------------------------------------------------------
--- Mouseover highlight is now owned by MSUF.Highlight (Engine/Elements/
--- MSUF_UF_Highlight.lua): coldpath config cache + warmpath Show/Hide on
--- OnEnter/OnLeave. The old per-frame EnumerateFrames "fix" scan is gone.
--- These shims keep external callers working; they just repaint the cache.
--- ---------------------------------------------------------------------------
function MSUF.MSUF_FixMouseoverHighlightBindings()
    if _G.MSUF_RefreshMouseoverHighlight then
        _G.MSUF_RefreshMouseoverHighlight()
    end
end
MSUF.MSUF_ScheduleMouseoverHighlightFix = MSUF.MSUF_FixMouseoverHighlightBindings


--- -
--- Color Get/Set API - data-driven where possible, hand-written for complex logic
--- -

--- Helper: simple RGB get from DB keys with defaults
local function _getRGB(rKey, gKey, bKey, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    return g[rKey] or defR, g[gKey] or defG, g[bKey] or defB
end

--- Helper: simple RGBA get from DB keys with defaults
local function _getRGBA(rKey, gKey, bKey, aKey, defR, defG, defB, defA)
    local g = _general()
    if not g then return defR, defG, defB, defA end
    return g[rKey] or defR, g[gKey] or defG, g[bKey] or defB, g[aKey] or defA
end

--- Helper: simple RGB set + PushVisualUpdates
local function _setRGB(rKey, gKey, bKey, r, g, b, defR, defG, defB)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR
    gen[gKey] = g or defG
    gen[bKey] = b or defB
    PushVisualUpdates()
end

--- Helper: simple RGBA set + PushVisualUpdates
local function _setRGBA(rKey, gKey, bKey, aKey, r, g, b, a, defR, defG, defB, defA)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR; gen[gKey] = g or defG; gen[bKey] = b or defB; gen[aKey] = a or defA
    PushVisualUpdates()
end

--- Helper: RGB get with palette fallback
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

--- Helper: RGB get with tonumber guards + palette fallback
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

--- - Global Font Color -
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

--- - Castbar Text Color -
local function GetCastbarTextColor()
    local g = _general()
    if not g then return GetGlobalFontColor() end
    if g.castbarFontR and g.castbarFontG and g.castbarFontB then return g.castbarFontR, g.castbarFontG, g.castbarFontB end
    return GetGlobalFontColor()
end
ExportPublic("MSUF_GetCastbarTextColor", GetCastbarTextColor)
local function SetCastbarTextColor(r, g, b)
    _setRGB("castbarFontR", "castbarFontG", "castbarFontB", r, g, b, 1, 1, 1)
end
local function ResetCastbarTextColorToGlobal()
    local g = _general(); if not g then return end
    g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil; PushVisualUpdates()
end

--- - Castbar Border Color -
local function GetCastbarBorderColor() return _getRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", 0, 0, 0, 1) end
local function SetCastbarBorderColor(r, g, b, a) _setRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", r, g, b, a, 0, 0, 0, 1) end
local function ResetCastbarBorderColor()
    local g = _general(); if not g then return end
    g.castbarBorderR, g.castbarBorderG, g.castbarBorderB, g.castbarBorderA = nil, nil, nil, nil; PushVisualUpdates()
end

--- - Castbar Background Color -
local function GetCastbarBackgroundColor()
    local g = _general()
    if not g then return 0.10, 0.10, 0.10, 0.85 end
    return tonumber(g.castbarBgR) or 0.10, tonumber(g.castbarBgG) or 0.10, tonumber(g.castbarBgB) or 0.10, tonumber(g.castbarBgA) or 0.85
end
ExportPublic("MSUF_GetCastbarBackgroundColor", GetCastbarBackgroundColor)
local function SetCastbarBackgroundColor(r, g, b, a) _setRGBA("castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA", r, g, b, a, 0.10, 0.10, 0.10, 0.85) end
local function ResetCastbarBackgroundColor()
    local g = _general(); if not g then return end
    g.castbarBgR, g.castbarBgG, g.castbarBgB, g.castbarBgA = nil, nil, nil, nil; PushVisualUpdates()
end

--- - Cast Colors (interruptible / non-interruptible / feedback) -
local function GetInterruptibleCastColor() return _getRGBPalette("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", "castbarInterruptibleColor", "turquoise", 0, 0.9, 0.8) end
ExportPublic("MSUF_GetInterruptibleCastColor", GetInterruptibleCastColor)
local function SetInterruptibleCastColor(r, g, b) _setRGB("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", r, g, b, 0, 0.9, 0.8) end
local function GetNonInterruptibleCastColor() return _getRGBTonumber("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", "castbarNonInterruptibleColor", "red", 0.4, 0.01, 0.01) end
ExportPublic("MSUF_GetNonInterruptibleCastColor", GetNonInterruptibleCastColor)
local function SetNonInterruptibleCastColor(r, g, b) _setRGB("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", r, g, b, 0.4, 0.01, 0.01) end
local function GetInterruptFeedbackCastColor() return _getRGBTonumber("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", "castbarInterruptFeedbackColor", "yellow", 1.0, 0.82, 0.0) end
local function SetInterruptFeedbackCastColor(r, g, b) _setRGB("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", r, g, b, 1.0, 0.82, 0.0) end

--- - Player Castbar Override -
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

--- - Class Colors -
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

--- - Class Bar Background Color -
local function GetClassBarBgColor() return _getRGB("classBarBgR", "classBarBgG", "classBarBgB", 0, 0, 0) end
local function SetClassBarBgColor(r, g, b) _setRGB("classBarBgR", "classBarBgG", "classBarBgB", r, g, b, 0, 0, 0) end
local function ResetClassBarBgColor()
    local g = _general(); if not g then return end
    g.classBarBgR, g.classBarBgG, g.classBarBgB = nil, nil, nil; PushVisualUpdates()
end

--- - Bar BG Match HP -
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

--- - NPC Colors -
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

--- - Pet Frame Color -
local function GetPetFrameColor() return _getRGB("petFrameColorR", "petFrameColorG", "petFrameColorB", 0, 0.8, 0) end
local function SetPetFrameColor(r, g, b) _setRGB("petFrameColorR", "petFrameColorG", "petFrameColorB", r, g, b, 0, 0.8, 0) end

--- - Absorb / Heal-Absorb Overlay Colors -
--- Keys aligned with the readers used by main UF, GF Render, GF Core preview,
--- GF AuraPreview, and the bar-color reset in Options_Colors. The picker used
--- to write `absorbColor*` / `healAbsorbColor*` while every reader consumed
--- `absorbBarColor*` / `healAbsorbBarColor*` - so color changes never landed.
--- One-time migration of the legacy keys is done in MSUF_Defaults.
local function GetAbsorbOverlayColor()         return _getRGBA("absorbBarColorR",     "absorbBarColorG",     "absorbBarColorB",     "absorbBarColorA",     1.0, 1.0, 1.0, 0.45) end
local function SetAbsorbOverlayColor(r, g, b, a)      _setRGBA("absorbBarColorR",     "absorbBarColorG",     "absorbBarColorB",     "absorbBarColorA",     r, g, b, a, 1.0, 1.0, 1.0, 0.45) end
local function GetHealAbsorbOverlayColor()     return _getRGBA("healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA", 0.7, 0.0, 0.0, 0.45) end
local function SetHealAbsorbOverlayColor(r, g, b, a)  _setRGBA("healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA", r, g, b, a, 0.7, 0.0, 0.0, 0.45) end

--- - Power Bar Background -
local function GetPowerBarBackgroundColor()
    local g = _general()
    if not g then return 0, 0, 0 end
    return tonumber(g.powerBarBgColorR) or 0, tonumber(g.powerBarBgColorG) or 0, tonumber(g.powerBarBgColorB) or 0
end
local function SetPowerBarBackgroundColor(r, g, b) _setRGB("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", r, g, b, 0, 0, 0) end
local function GetPowerBarBackgroundMatchHP() return (_general() or {}).powerBarBgMatchBarColor and true or false end
local function SetPowerBarBackgroundMatchHP(v) local g = _general(); if g then g.powerBarBgMatchBarColor = v and true or false; PushVisualUpdates() end end

--- - Aggro Border -
local function GetAggroBorderColor()
    local g = _general()
    if not g then return 1.0, 0.5, 0.0 end
    return tonumber(g.hlAggroColorR) or tonumber(g.aggroBorderColorR) or tonumber(g.aggroBorderR) or 1.0,
           tonumber(g.hlAggroColorG) or tonumber(g.aggroBorderColorG) or tonumber(g.aggroBorderG) or 0.5,
           tonumber(g.hlAggroColorB) or tonumber(g.aggroBorderColorB) or tonumber(g.aggroBorderB) or 0.0
end
local function SetAggroBorderColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.hlAggroColorR = r or 1.0
    gen.hlAggroColorG = g or 0.5
    gen.hlAggroColorB = b or 0.0
    gen.aggroBorderColorR, gen.aggroBorderColorG, gen.aggroBorderColorB = gen.hlAggroColorR, gen.hlAggroColorG, gen.hlAggroColorB
    gen.aggroBorderR, gen.aggroBorderG, gen.aggroBorderB = gen.hlAggroColorR, gen.hlAggroColorG, gen.hlAggroColorB
    PushVisualUpdates()
end

local function GetBarOutlineColor() return _getRGB("barOutlineColorR", "barOutlineColorG", "barOutlineColorB", 0, 0, 0) end
local function SetBarOutlineColor(r, g, b)
    local general = _general()
    if general then
        general.barOutlineColorMode = nil
        general.barOutlineColorA = 1
    end
    _setRGB("barOutlineColorR", "barOutlineColorG", "barOutlineColorB", r, g, b, 0, 0, 0)
end
ExportPublic("MSUF_GetBarOutlineColor", GetBarOutlineColor)

--- -
--- Export table
--- -
MSUF._colorsAPI = {
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
    GetBarOutlineColor              = GetBarOutlineColor,
    SetBarOutlineColor              = SetBarOutlineColor,
    GetPowerBarBackgroundMatchHP    = GetPowerBarBackgroundMatchHP,
    SetPowerBarBackgroundMatchHP    = SetPowerBarBackgroundMatchHP,
}
MSUF.Public.Colors = MSUF._colorsAPI
