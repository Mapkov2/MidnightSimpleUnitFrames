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
local CreateFrame           = _G.CreateFrame
local InCombatLockdown      = _G.InCombatLockdown
local RunNextFrame          = _G.MSUF_RunNextFrame or _G.MSUF_Core_RunNextFrame or function(fn)
    if type(fn) ~= "function" then return end
    C_Timer.After(0, fn)
end
local COLOR_PUSH_DELAY      = 0.04

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
    --- Full-profile imports deliberately keep the MSUF_DB root stable while
    --- replacing its `general` child. Validate both identities so getters and
    --- setters never keep operating on the detached pre-import table.
    if db and _cachedDB == db and _cachedGen == db.general then
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
---
--- Helper: apply visual updates (COALESCED)
--- Color picker drag can fire 30+ times/sec. Without coalescing,
--- each drag fires UpdateAllFonts + RefreshAllFrames + ... per tick.
--- We batch locally; this runtime no longer depends on the global scheduler.
---
local _pushPending = false
local _castbarPushPending = false
local _colorCombatDeferred = false
local _castbarCombatDeferred = false
local _combatDeferFrame
local PushVisualUpdates
local PushCastbarVisualUpdates

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function EnsureCombatDeferFrame()
    if _combatDeferFrame or type(CreateFrame) ~= "function" then
        return _combatDeferFrame
    end
    _combatDeferFrame = CreateFrame("Frame")
    _combatDeferFrame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local color = _colorCombatDeferred
        local castbar = _castbarCombatDeferred
        _colorCombatDeferred = false
        _castbarCombatDeferred = false
        if color and PushVisualUpdates then PushVisualUpdates() end
        if castbar and PushCastbarVisualUpdates then PushCastbarVisualUpdates() end
    end)
    return _combatDeferFrame
end

local function DeferVisualFlushUntilCombatEnds(kind)
    if kind == "castbar" then
        _castbarCombatDeferred = true
    else
        _colorCombatDeferred = true
    end
    local frame = EnsureCombatDeferFrame()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return true
end

local function _Call(fn, ...)
    if type(fn) ~= "function" then return false end
    fn(...)
    return true
end

local function _RefreshUnitFrameColors()
    if _Call(_G.MSUF_RefreshAllFrameColors) then return true end
    if _Call(MSUF and MSUF.UF and MSUF.UF.RefreshColors) then return true end
    -- Legacy-only fallback: without UF.RefreshColors there is no Config.serial
    -- advance to invalidate the lazy settings cache for us.
    _Call(_G.MSUF_UFCore_RefreshSettingsCache, "COLOR_CHANGE")
    local did = _Call(_G.MSUF_RefreshAllIdentityColors)
    did = _Call(_G.MSUF_RefreshAllPowerTextColors) or did
    return did
end

local function _RefreshAllBarBackgroundVisuals(colorsAlreadyRefreshed)
    local applyBg = _G.MSUF_ApplyBarBackgroundVisual
    local refreshHP = _G.MSUF_UFCore_RefreshHealthBarColor
    local syncMissing = _G.MSUF_Alpha_UpdatePreserveMissingHP
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" or type(applyBg) ~= "function" then return end

    for _, frame in pairs(frames) do
        if frame and (frame.hpBarBG or frame.powerBarBG or frame.bg) then
            if colorsAlreadyRefreshed ~= true and type(refreshHP) == "function" and frame.hpBar then
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
    if InCombat() then
        _pushPending = false
        return DeferVisualFlushUntilCombatEnds("color")
    end
    --- PERF (4.22 Beta hotfix): pending flag stays TRUE during the entire
    --- flush body. Pending dedup remains correct: any PushVisualUpdates()
    --- call during this flush is dropped, and the next one after we finish
    --- schedules normally. Cleared at END.
    ---
    --- Same defense-in-depth pattern as _gfRosterFlush.
    --- UF.RefreshColors advances Config.serial before elements read color
    --- settings, so the lazy settings cache is rebuilt once on first use.
    local colorsAlreadyRefreshed = _RefreshUnitFrameColors()
    _Call(_RefreshAllBarBackgroundVisuals, colorsAlreadyRefreshed)
    _Call(_G.MSUF_UpdateCastbarVisuals)
    if MSUF.MSUF_ApplyGameplayVisuals then
        _Call(MSUF.MSUF_ApplyGameplayVisuals)
    end
    --- Group Frames have their own render/dirty pipeline; refresh it explicitly
    --- so shared bar-color swatches (absorb/heal-absorb, borders, etc.) live-apply.
    do
        local gf = MSUF and MSUF.GF
        local refreshGFColors = (gf and gf.RefreshColors) or _G.MSUF_GF_RefreshColors
        if type(refreshGFColors) == "function" then
            _Call(refreshGFColors)
        end
    end

    --- Sync highlight priority stripe colors when border colors change.
    _Call(_G.MSUF_PrioRows_Reinit)

    --- UF.RefreshColors already includes both Borders and Power. Running the
    --- legacy outline fanout afterwards would compile every unit spec and walk
    --- every frame a second time. Keep it only for the legacy fallback path,
    --- where the consolidated UF color refresh is unavailable.
    if colorsAlreadyRefreshed ~= true then
        local applyAll = _G.MSUF_ApplyBarOutlineThickness_All
        _Call(applyAll)
    end
    _Call(_G.MSUF_ApplyRoundedUnitframes)
    _Call(_G.MSUF_UFPreview_RequestRefresh, "MSUF_COLOR_CHANGE")

    --- Repaint the mouseover highlight cache so colour/size edits apply live.
    _Call(_G.MSUF_RefreshMouseoverHighlight)

    --- Pending flag cleared at END (see header comment for rationale).
    _pushPending = false
end

local function _PushCastbarVisuals_Flush()
    if InCombat() then
        _castbarPushPending = false
        return DeferVisualFlushUntilCombatEnds("castbar")
    end
    if not _Call(_G.MSUF_UpdateCastbarVisuals) then
        _Call(_G.MSUF_UpdateBossCastbarPreview)
    end
    _Call(_G.MSUF_RefreshAllCastTargetTextColors)
    _Call(_G.MSUF_UFPreview_RequestRefresh, "MSUF_CASTBAR_COLOR_CHANGE")
    _castbarPushPending = false
end

PushVisualUpdates = function()
    if InCombat() then return DeferVisualFlushUntilCombatEnds("color") end
    if _pushPending then return end
    _pushPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(COLOR_PUSH_DELAY, _PushVisualUpdates_Flush)
    else
        RunNextFrame(_PushVisualUpdates_Flush)
    end
end

PushCastbarVisualUpdates = function()
    if InCombat() then return DeferVisualFlushUntilCombatEnds("castbar") end
    if _castbarPushPending then return end
    _castbarPushPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(COLOR_PUSH_DELAY, _PushCastbarVisuals_Flush)
    else
        RunNextFrame(_PushCastbarVisuals_Flush)
    end
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
local function _setRGB(rKey, gKey, bKey, r, g, b, defR, defG, defB, pushFn)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR
    gen[gKey] = g or defG
    gen[bKey] = b or defB
    if type(pushFn) == "function" then pushFn() else PushVisualUpdates() end
end

--- Helper: simple RGBA set + PushVisualUpdates
local function _setRGBA(rKey, gKey, bKey, aKey, r, g, b, a, defR, defG, defB, defA, pushFn)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR; gen[gKey] = g or defG; gen[bKey] = b or defB; gen[aKey] = a or defA
    if type(pushFn) == "function" then pushFn() else PushVisualUpdates() end
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
    _setRGB("castbarFontR", "castbarFontG", "castbarFontB", r, g, b, 1, 1, 1, PushCastbarVisualUpdates)
end
local function ResetCastbarTextColorToGlobal()
    local g = _general(); if not g then return end
    g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil; PushCastbarVisualUpdates()
end

--- - Castbar Target Name Color -
--- The fourth return value preserves the legacy class-color fallback until a
--- user explicitly chooses a custom target-name color.
local function GetCastbarTargetNameColor()
    local g = _general()
    if not g then return 1, 1, 1, false end
    local r = tonumber(g.castbarTargetNameR)
    local green = tonumber(g.castbarTargetNameG)
    local b = tonumber(g.castbarTargetNameB)
    if r ~= nil and green ~= nil and b ~= nil then return r, green, b, true end
    return 1, 1, 1, false
end
ExportPublic("MSUF_GetCastbarTargetNameColor", GetCastbarTargetNameColor)
local function SetCastbarTargetNameColor(r, g, b)
    _setRGB("castbarTargetNameR", "castbarTargetNameG", "castbarTargetNameB", r, g, b, 1, 1, 1, PushCastbarVisualUpdates)
end
local function ResetCastbarTargetNameColor()
    local g = _general(); if not g then return end
    g.castbarTargetNameR, g.castbarTargetNameG, g.castbarTargetNameB = nil, nil, nil
    PushCastbarVisualUpdates()
end

--- - Per-castbar detail text colors -
--- The castbar font path already reads these keys directly. This API exists so
--- the Options surfaces and the cast-target recolor path resolve them the same
--- way, and so an unset detail keeps inheriting the shared castbar text color
--- instead of being pinned. A complete triple is the opt-in signal, matching
--- the target-name contract above.
local CASTBAR_DETAIL_PREFIX = {
    player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast",
}
local function CastbarDetailColorKey(unit, detail)
    if type(unit) ~= "string" or type(detail) ~= "string" or detail == "" then return nil end
    -- Boss frames arrive as boss1..boss5 from the driver but share one config row.
    local prefix = CASTBAR_DETAIL_PREFIX[unit] or (unit:match("^boss%d*$") and "bossCast") or nil
    if not prefix then return nil end
    return prefix .. detail .. "Color"
end
local function GetCastbarDetailTextColor(unit, detail)
    local g = _general()
    if not g then return 1, 1, 1, false end
    local key = CastbarDetailColorKey(unit, detail)
    if not key then return 1, 1, 1, false end
    local r, green, b = tonumber(g[key .. "R"]), tonumber(g[key .. "G"]), tonumber(g[key .. "B"])
    if r ~= nil and green ~= nil and b ~= nil then return r, green, b, true end
    return 1, 1, 1, false
end
ExportPublic("MSUF_GetCastbarDetailTextColor", GetCastbarDetailTextColor)
local function SetCastbarDetailTextColor(unit, detail, r, g, b)
    local key = CastbarDetailColorKey(unit, detail)
    if not key then return end
    _setRGB(key .. "R", key .. "G", key .. "B", r, g, b, 1, 1, 1, PushCastbarVisualUpdates)
end
ExportPublic("MSUF_SetCastbarDetailTextColor", SetCastbarDetailTextColor)
local function ResetCastbarDetailTextColor(unit, detail)
    local gen = _general()
    if not gen then return end
    local key = CastbarDetailColorKey(unit, detail)
    if not key then return end
    gen[key .. "R"], gen[key .. "G"], gen[key .. "B"] = nil, nil, nil
    PushCastbarVisualUpdates()
end
ExportPublic("MSUF_ResetCastbarDetailTextColor", ResetCastbarDetailTextColor)

--- - Castbar Border Color -
local function GetCastbarBorderColor() return _getRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", 0, 0, 0, 1) end
local function SetCastbarBorderColor(r, g, b, a) _setRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", r, g, b, a, 0, 0, 0, 1, PushCastbarVisualUpdates) end
local function ResetCastbarBorderColor()
    local g = _general(); if not g then return end
    g.castbarBorderR, g.castbarBorderG, g.castbarBorderB, g.castbarBorderA = nil, nil, nil, nil; PushCastbarVisualUpdates()
end

--- - Castbar Background Color -
local function GetCastbarBackgroundColor()
    local g = _general()
    if not g then return 0.10, 0.10, 0.10, 0.85 end
    return tonumber(g.castbarBgR) or 0.10, tonumber(g.castbarBgG) or 0.10, tonumber(g.castbarBgB) or 0.10, tonumber(g.castbarBgA) or 0.85
end
ExportPublic("MSUF_GetCastbarBackgroundColor", GetCastbarBackgroundColor)
local function SetCastbarBackgroundColor(r, g, b, a) _setRGBA("castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA", r, g, b, a, 0.10, 0.10, 0.10, 0.85, PushCastbarVisualUpdates) end
local function ResetCastbarBackgroundColor()
    local g = _general(); if not g then return end
    g.castbarBgR, g.castbarBgG, g.castbarBgB, g.castbarBgA = nil, nil, nil, nil; PushCastbarVisualUpdates()
end

--- - Cast Colors (interruptible / non-interruptible / feedback) -
local function GetInterruptibleCastColor() return _getRGBPalette("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", "castbarInterruptibleColor", "turquoise", 0, 0.9, 0.8) end
ExportPublic("MSUF_GetInterruptibleCastColor", GetInterruptibleCastColor)
local function SetInterruptibleCastColor(r, g, b) _setRGB("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", r, g, b, 0, 0.9, 0.8, PushCastbarVisualUpdates) end
local function GetNonInterruptibleCastColor() return _getRGBTonumber("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", "castbarNonInterruptibleColor", "red", 0.4, 0.01, 0.01) end
ExportPublic("MSUF_GetNonInterruptibleCastColor", GetNonInterruptibleCastColor)
local function SetNonInterruptibleCastColor(r, g, b) _setRGB("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", r, g, b, 0.4, 0.01, 0.01, PushCastbarVisualUpdates) end
local function GetInterruptFeedbackCastColor() return _getRGBTonumber("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", "castbarInterruptFeedbackColor", "yellow", 1.0, 0.82, 0.0) end
ExportPublic("MSUF_GetInterruptFeedbackCastColor", GetInterruptFeedbackCastColor)
local function SetInterruptFeedbackCastColor(r, g, b) _setRGB("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", r, g, b, 1.0, 0.82, 0.0, PushCastbarVisualUpdates) end
local function GetInterruptUnavailableCastColor() return _getRGBTonumber("castbarInterruptUnavailableR", "castbarInterruptUnavailableG", "castbarInterruptUnavailableB", "castbarInterruptUnavailableColor", nil, 1.0, 0.494117647, 0.137254902) end
ExportPublic("MSUF_GetInterruptUnavailableCastColor", GetInterruptUnavailableCastColor)
local function SetInterruptUnavailableCastColor(r, g, b) _setRGB("castbarInterruptUnavailableR", "castbarInterruptUnavailableG", "castbarInterruptUnavailableB", r, g, b, 1.0, 0.494117647, 0.137254902, PushCastbarVisualUpdates) end

--- - Player Castbar Override -
local function GetPlayerCastbarOverrideEnabled() return (_general() or {}).playerCastbarOverrideEnabled and true or false end
local function SetPlayerCastbarOverrideEnabled(enabled)
    local g = _general(); if not g then return end; g.playerCastbarOverrideEnabled = enabled and true or false; PushCastbarVisualUpdates()
end
local function GetPlayerCastbarOverrideMode() return (_general() or {}).playerCastbarOverrideMode or "COLOR" end
local function SetPlayerCastbarOverrideMode(mode)
    local g = _general(); if not g then return end; g.playerCastbarOverrideMode = mode; PushCastbarVisualUpdates()
end
local function GetPlayerCastbarOverrideColor() return _getRGB("playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB", 0.0, 0.6, 1.0) end
local function SetPlayerCastbarOverrideColor(r, g, b) _setRGB("playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB", r, g, b, 0.0, 0.6, 1.0, PushCastbarVisualUpdates) end

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
local function GetClassBarBgColor() return _getRGBA("classBarBgR", "classBarBgG", "classBarBgB", "classBarBgA", 0, 0, 0, 1) end
local function SetClassBarBgColor(r, g, b, a) _setRGBA("classBarBgR", "classBarBgG", "classBarBgB", "classBarBgA", r, g, b, a, 0, 0, 0, 1) end
local function ResetClassBarBgColor()
    local g = _general(); if not g then return end
    g.classBarBgR, g.classBarBgG, g.classBarBgB, g.classBarBgA = nil, nil, nil, nil; PushVisualUpdates()
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
local function GetNPCClassColorBar() local g = _general(); return g and g.npcClassColorBar == true or false end
local function SetNPCClassColorBar(v) local g = _general(); if g then g.npcClassColorBar = v and true or false; PushVisualUpdates() end end
local function ResetNPCTypeColors()
    local db = _G.MSUF_DB
    local colors = db and db.npcColors
    if type(colors) == "table" then
        for i = 1, #NPC_TYPE_KEYS do colors[NPC_TYPE_KEYS[i]] = nil end
        if next(colors) == nil then db.npcColors = nil end
    end
    PushVisualUpdates()
end
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
    return _getRGBA("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", "powerBarBgColorA", 0, 0, 0, 1)
end
local function SetPowerBarBackgroundColor(r, g, b, a) _setRGBA("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", "powerBarBgColorA", r, g, b, a, 0, 0, 0, 1) end
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
    PushCastbarVisualUpdates        = PushCastbarVisualUpdates,
    GetGlobalFontColor              = GetGlobalFontColor,
    SetGlobalFontColor              = SetGlobalFontColor,
    ResetGlobalFontToPalette        = ResetGlobalFontToPalette,
    GetCastbarTextColor             = GetCastbarTextColor,
    SetCastbarTextColor             = SetCastbarTextColor,
    ResetCastbarTextColorToGlobal   = ResetCastbarTextColorToGlobal,
    GetCastbarTargetNameColor       = GetCastbarTargetNameColor,
    SetCastbarTargetNameColor       = SetCastbarTargetNameColor,
    ResetCastbarTargetNameColor     = ResetCastbarTargetNameColor,
    GetCastbarDetailTextColor       = GetCastbarDetailTextColor,
    SetCastbarDetailTextColor       = SetCastbarDetailTextColor,
    ResetCastbarDetailTextColor     = ResetCastbarDetailTextColor,
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
    GetInterruptUnavailableCastColor = GetInterruptUnavailableCastColor,
    SetInterruptUnavailableCastColor = SetInterruptUnavailableCastColor,
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
    GetNPCClassColorBar             = GetNPCClassColorBar,
    SetNPCClassColorBar             = SetNPCClassColorBar,
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
