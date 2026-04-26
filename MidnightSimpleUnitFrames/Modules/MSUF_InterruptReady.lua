-- MSUF_InterruptReady.lua
-- =============================================================================
-- Single source of truth for the player's interrupt spell + readiness state.
-- Provides:
--   * MSUF_KickReady_GetSpellID()      -> integer | nil
--   * MSUF_KickReady_GetSpellName()    -> string  | nil
--   * MSUF_KickReady_IsReady()         -> boolean (plain, never secret)
--   * MSUF_KickReady_Init()            -> ensure resolved (idempotent)
--   * MSUF_KickReady_RefreshAll()      -> repaint every registered castbar
--   * MSUF_KickReady_RefreshFrame(f,s) -> repaint a single castbar (and arm CD timer)
--   * MSUF_KickReady_ApplyLayout(f)    -> create / position the indicator dot on a frame
--   * MSUF_KickReady_Debug()           -> printable diagnostic dump
--
-- Architecture:
--   * Class+spec hard-coded interrupt table (mirrors MidnightFocusInterrupt's
--     INTERRUPT_BY_CLASS — proven correct for 12.0.5 / Midnight, including
--     Rogue Kick 1766). Class identity is the source of truth — no
--     IsSpellKnown / actionbar guessing games.
--   * Cooldown read via C_Spell.GetSpellCooldownDuration(id):IsZero(). Returns
--     a plain boolean even when the underlying duration object is opaque,
--     so it is always safe to use in Lua-side logic.
--   * Color via C_CurveUtil.EvaluateColorFromBoolean and visibility via
--     SetAlphaFromBoolean — both accept secret booleans cleanly.
--   * Per-frame C_Timer.After(remaining + 0.05, refresh) for the CD-end repaint
--     so the indicator turns green the moment Kick comes off cooldown without
--     waiting for SPELL_UPDATE_COOLDOWN to retrigger.
--   * Zero work when feature is disabled: registered events are dropped and
--     no per-frame state is created.
--
-- Secret-safety contract:
--   * No arithmetic / equality / boolean tests on values returned by
--     UnitChannelInfo / UnitCastingInfo. We rely exclusively on the cast
--     frame's own `frame.isNotInterruptible` plain boolean, which the
--     castbar driver already cleanses via DetectNonInterruptible.
--   * GetSpellCooldownDuration(id) returns a duration object; we only call
--     :IsZero() on it (returns plain boolean). No GCD math is performed.
-- =============================================================================

local _G = _G
local C_Spell           = _G.C_Spell
local C_Timer           = _G.C_Timer
local C_CurveUtil       = _G.C_CurveUtil
local CreateFrame       = _G.CreateFrame
local UnitClass         = _G.UnitClass
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo

-- =============================================================================
-- Interrupt spell table (mirrors MidnightFocusInterrupt-3.14.2)
-- =============================================================================

local INTERRUPT_BY_CLASS = {
    DEATHKNIGHT = { DEFAULT = 47528  }, -- Mind Freeze
    DEMONHUNTER = { DEFAULT = 183752 }, -- Disrupt
    DRUID       = { DEFAULT = 106839, BALANCE = 78675 }, -- Skull Bash / Solar Beam (Balance)
    EVOKER      = { DEFAULT = 351338 }, -- Quell
    HUNTER      = { DEFAULT = 147362, SURVIVAL = 187707 }, -- Counter Shot / Muzzle (Survival)
    MAGE        = { DEFAULT = 2139   }, -- Counterspell
    MONK        = { DEFAULT = 116705 }, -- Spear Hand Strike
    PALADIN     = { DEFAULT = 96231  }, -- Rebuke
    PRIEST      = { DEFAULT = 15487  }, -- Silence
    ROGUE       = { DEFAULT = 1766   }, -- Kick
    SHAMAN      = { DEFAULT = 57994  }, -- Wind Shear
    WARLOCK     = { DEFAULT = 19647, DEMONOLOGY = 119914 }, -- Spell Lock / Axe Toss (Demo)
    WARRIOR     = { DEFAULT = 6552   }, -- Pummel
}

-- Spec IDs that override DEFAULT (matches reference addon's behavior).
local SPEC_OVERRIDE = {
    [102] = "BALANCE",      -- Balance Druid
    [255] = "SURVIVAL",     -- Survival Hunter
    [266] = "DEMONOLOGY",   -- Demonology Warlock
}

-- =============================================================================
-- Module state
-- =============================================================================

local _state = {
    spellID    = nil,    -- resolved interrupt spell id (number)
    spellName  = nil,    -- resolved interrupt spell name (string)
    iconID     = nil,    -- resolved interrupt spell icon (texture id)
    classToken = nil,    -- "ROGUE", "MAGE", ...
    specID     = nil,    -- numeric spec id
    resolved   = false,  -- has Resolve() succeeded at least once?
    eventsOn   = false,  -- are SPELL_UPDATE_COOLDOWN etc. currently registered?
}

-- Track every MSUF castbar frame that has had ApplyLayout() called, so
-- RefreshAll() (and global cooldown sweeps) can iterate them cheaply.
local _registeredFrames = {}

-- =============================================================================
-- Helpers
-- =============================================================================

local function _GetCfg()
    -- The Castbar Options menu writes the kickReady* keys into MSUF_DB.general
    -- (via its local `G()` accessor). Read from the same place — DO NOT use
    -- MSUF_DB.castbarVisuals here, otherwise the toggles will never apply.
    local db = _G.MSUF_DB
    if not db then return nil end
    return db.general
end

local function _AnyShowEnabled(cfg)
    if not cfg then return false end
    return cfg.kickReadyShowTarget == true
        or cfg.kickReadyShowFocus  == true
        or cfg.kickReadyShowBoss   == true
end

local function _ShowOnUnit(cfg, unit)
    if not cfg or not unit then return false end
    if unit == "target" then return cfg.kickReadyShowTarget == true end
    if unit == "focus"  then return cfg.kickReadyShowFocus  == true end
    if type(unit) == "string" and unit:sub(1, 4) == "boss" then
        return cfg.kickReadyShowBoss == true
    end
    return false
end

-- =============================================================================
-- Spell resolution
-- =============================================================================

local function Resolve()
    -- Class
    local _, classToken = UnitClass("player")
    if not classToken then return end
    _state.classToken = classToken

    local entry = INTERRUPT_BY_CLASS[classToken]
    if not entry then
        _state.spellID   = nil
        _state.spellName = nil
        _state.iconID    = nil
        _state.resolved  = false
        return
    end

    -- Spec
    local specID
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx then
            local sid = GetSpecializationInfo(idx)
            if type(sid) == "number" then specID = sid end
        end
    end
    _state.specID = specID

    -- Pick spell id
    local key = specID and SPEC_OVERRIDE[specID] or "DEFAULT"
    local id  = entry[key] or entry.DEFAULT
    _state.spellID = id

    -- Resolve name + icon (best-effort; names can lag right at login)
    if id and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then
            _state.spellName = info.name
            _state.iconID    = info.iconID
        end
    end

    _state.resolved = (id ~= nil)
end

-- =============================================================================
-- Cooldown query (secret-safe)
-- =============================================================================
-- IMPORTANT: In 12.0.5/Midnight, dur:IsZero() returns a SECRET-TAINTED boolean
-- when the spell ID belongs to a player interrupt. The value cannot be tested
-- via ==, ~=, `if`, `not`, or any Lua-side operation. It can ONLY be passed
-- through to C-side helpers that accept secret booleans:
--   * SetAlphaFromBoolean(b, trueAlpha, falseAlpha)
--   * C_CurveUtil.EvaluateColorFromBoolean(b, trueMixin, falseMixin)
--   * SetShownSafe / SetEnabledFromBoolean (where applicable)
--
-- Returns nil if the spell isn't resolved yet — callers must guard.

local function _GetReadyBoolSecret()
    local id = _state.spellID
    if not id then return nil end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end

    local dur = C_Spell.GetSpellCooldownDuration(id)
    if not dur or not dur.IsZero then return nil end
    return dur:IsZero()  -- secret bool — DO NOT compare in Lua
end

-- =============================================================================
-- Color resolution (secret-safe via EvaluateColorFromBoolean)
-- =============================================================================

local READY_COLOR     = { r = 0.20, g = 1.00, b = 0.20, a = 1 }
local COOLDOWN_COLOR  = { r = 1.00, g = 0.20, b = 0.20, a = 1 }

local _readyColorMixin, _cooldownColorMixin
local function _EnsureColorMixins()
    if _readyColorMixin then return end
    if not _G.CreateColor then return end
    _readyColorMixin    = _G.CreateColor(READY_COLOR.r,    READY_COLOR.g,    READY_COLOR.b,    READY_COLOR.a)
    _cooldownColorMixin = _G.CreateColor(COOLDOWN_COLOR.r, COOLDOWN_COLOR.g, COOLDOWN_COLOR.b, COOLDOWN_COLOR.a)
end

-- =============================================================================
-- Indicator: two visual styles
-- =============================================================================
-- Style "border" (default): tint the castbar's own outline (frame._msufOutline)
--   green when the player's interrupt is ready, red when on cooldown. The
--   castbar's normal fill colors from the Color menu remain untouched —
--   only the outline edges flip color while an interruptible cast is active
--   and the unit is in scope.
--
-- Style "box": a small colored square parented to frame.statusBar, sized
--   to the castbar height (or to the manual slider when auto-size is off).
--   Same color logic. No icon.
--
-- Either style respects the "Use castbar colors" toggle: when on, ready/CD
-- colors come from MSUF_ResolveCastbarColors() (the user's interruptible /
-- non-interruptible Color-menu values) instead of the hardcoded green/red.
--
-- When the indicator is OFF (toggle off, unit out of scope, no cast, or cast
-- not interruptible), the castbar's original outline color is restored via
-- MSUF_ApplyCastbarOutline(frame, true) and the box is hidden.

local function _CreateBox(frame)
    if not frame or not frame.statusBar then return nil end

    local parent = frame.statusBar
    local box = CreateFrame("Frame", nil, parent)
    box:SetFrameLevel(parent:GetFrameLevel() + 5)
    box:Hide()

    -- Single solid fill texture — the box IS the indicator (no icon).
    local fill = box:CreateTexture(nil, "OVERLAY", nil, 7)
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetAllPoints(box)
    fill:SetVertexColor(COOLDOWN_COLOR.r, COOLDOWN_COLOR.g, COOLDOWN_COLOR.b, COOLDOWN_COLOR.a)
    box.fill = fill

    return box
end

local function _PositionBox(box, frame, cfg)
    if not box or not frame or not frame.statusBar then return end

    local autoSize = cfg.kickReadyAutoSize
    if autoSize == nil then autoSize = true end

    local size
    if autoSize == true then
        local barHeight = frame.statusBar:GetHeight()
        if not barHeight or barHeight <= 0 then
            barHeight = frame:GetHeight() or 0
        end
        size = barHeight
        if not size or size < 12 then size = 12 end
        if size > 80 then size = 80 end
    else
        size = tonumber(cfg.kickReadySize) or 16
        if size < 8  then size = 8  end
        if size > 48 then size = 48 end
    end

    local anchor = cfg.kickReadyAnchor            or "RIGHT"
    local ox     = tonumber(cfg.kickReadyOffsetX) or 4
    local oy     = tonumber(cfg.kickReadyOffsetY) or 0

    local relPoint = anchor
    local boxPoint = anchor
    if anchor == "RIGHT"  then boxPoint = "LEFT"   end
    if anchor == "LEFT"   then boxPoint = "RIGHT"  end
    if anchor == "TOP"    then boxPoint = "BOTTOM" end
    if anchor == "BOTTOM" then boxPoint = "TOP"    end

    box:SetSize(size, size)
    box:ClearAllPoints()
    box:SetPoint(boxPoint, frame.statusBar, relPoint, ox, oy)
end

-- Resolve the active ready/cooldown ColorMixin pair.
--
-- Source of truth: the user's Colors menu entries
--   MSUF_DB.general.kickReadyColor    = { ["1"]=r, ["2"]=g, ["3"]=b }   (default green)
--   MSUF_DB.general.kickNotReadyColor = { ["1"]=r, ["2"]=g, ["3"]=b }   (default red)
-- These are written by MSUF_Options_Colors.lua and are the same swatches the
-- user sees under "Interrupt Ready Indicator" in the Colors menu — keeping
-- the indicator visually independent from the castbar fill colors.
--
-- Returns plain ColorMixins built fresh per call, so live edits to the
-- Colors menu propagate immediately on the next repaint without any
-- explicit invalidation hook.
local function _ResolveColorPair(_)
    _EnsureColorMixins()

    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not g or not _G.CreateColor then
        return _readyColorMixin, _cooldownColorMixin
    end

    local function _readKickColor(key, dr, dg, db)
        local c = g[key]
        if type(c) ~= "table" then return dr, dg, db end
        local r = tonumber(c["1"]) or tonumber(c[1]) or dr
        local gx = tonumber(c["2"]) or tonumber(c[2]) or dg
        local b = tonumber(c["3"]) or tonumber(c[3]) or db
        return r, gx, b
    end

    -- Defaults match the Colors-menu defaults (green / red).
    local rr, rg, rb = _readKickColor("kickReadyColor",    0, 1, 0)
    local cr, cg, cb = _readKickColor("kickNotReadyColor", 1, 0, 0)

    return _G.CreateColor(rr, rg, rb, 1), _G.CreateColor(cr, cg, cb, 1)
end

-- Read the user's configured castbar outline color (the same RGBA that
-- MSUF_ApplyCastbarOutline writes onto the four edge textures) and return
-- it as a fresh ColorMixin. Used as the "no tint" target when composing
-- via EvaluateColorFromBoolean — when the cast is non-interruptible the
-- edge textures end up with this exact colour, so the user sees their
-- normal castbar outline rather than our green/red indicator.
local function _GetUserOutlineMixin()
    if not _G.CreateColor then return nil end
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local r  = (g and tonumber(g.castbarBorderR)) or 0
    local gg = (g and tonumber(g.castbarBorderG)) or 0
    local b  = (g and tonumber(g.castbarBorderB)) or 0
    local a  = (g and tonumber(g.castbarBorderA)) or 1
    return _G.CreateColor(r, gg, b, a)
end

-- Secret-safe RGBA tuple for the edge / box fill.
--
-- This composes up to TWO C-side EvaluateColorFromBoolean calls so neither
-- secret-tainted argument (`readyBool` from C_Spell.GetSpellCooldownDuration,
-- `rawNI` from UnitCastingInfo.notInterruptible) ever flows through Lua
-- arithmetic, equality, or truthiness tests:
--
--   inner = EvaluateColorFromBoolean(readyBool, readyMixin, cdMixin)
--             -> picks our green or red indicator colour
--   final = EvaluateColorFromBoolean(rawNI,    userMixin,  inner)
--             -> when rawNI is true (cast is non-interruptible), returns
--                userMixin so the edge ends up with the user's normal
--                outline colour and the indicator is effectively absent.
--                When rawNI is false (interruptible), returns the inner
--                green/red mixin.
--
-- `userMixin` and `rawNI` are optional. When either is nil (e.g. caller
-- doesn't have rawNI yet, or CreateColor isn't available), the function
-- collapses to the single-step ready/cooldown selection.
local function _PickColor(readyMixin, cdMixin, readyBool, userMixin, rawNI)
    -- Plain-only fallback when the C-side selector or our two indicator
    -- mixins are missing. Cannot test readyBool here (would taint), so we
    -- bias toward cooldown — readyBool's nil-vs-not is decided later via
    -- C_CurveUtil only when it's safe to do so.
    if not (C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean) or not readyMixin or not cdMixin then
        if cdMixin and cdMixin.GetRGBA then
            return cdMixin:GetRGBA()
        end
        return COOLDOWN_COLOR.r, COOLDOWN_COLOR.g, COOLDOWN_COLOR.b, COOLDOWN_COLOR.a
    end

    -- Step 1: indicator colour (ready / cooldown). readyBool is passed
    -- straight to C — never observed in Lua.
    local indicator = C_CurveUtil.EvaluateColorFromBoolean(readyBool, readyMixin, cdMixin)

    -- Step 2 (optional): non-interruptible gate. When rawNI is provided we
    -- compose with the user's outline colour so a non-interruptible cast
    -- shows no indicator at all.
    if userMixin ~= nil and rawNI ~= nil then
        return C_CurveUtil.EvaluateColorFromBoolean(rawNI, userMixin, indicator):GetRGBA()
    end

    return indicator:GetRGBA()
end

-- Apply our color to the castbar's existing outline edges.
local function _TintCastbarOutline(frame, r, g, b, a)
    local o = frame and frame._msufOutline
    if not o then return false end
    if o.top    and o.top.SetVertexColor    then o.top:SetVertexColor(r, g, b, a)    end
    if o.bottom and o.bottom.SetVertexColor then o.bottom:SetVertexColor(r, g, b, a) end
    if o.left   and o.left.SetVertexColor   then o.left:SetVertexColor(r, g, b, a)   end
    if o.right  and o.right.SetVertexColor  then o.right:SetVertexColor(r, g, b, a)  end
    -- Mark so the hook on MSUF_ApplyCastbarOutline knows to re-tint.
    frame._kickReadyBorderTinted = true
    return true
end

-- Drop our tint and let the user's configured outline color reappear.
local function _RestoreCastbarOutline(frame)
    if not frame then return end
    if not frame._kickReadyBorderTinted then return end
    frame._kickReadyBorderTinted = nil
    if type(_G.MSUF_ApplyCastbarOutline) == "function" then
        _G.MSUF_ApplyCastbarOutline(frame, true)
    end
end

local function _GetStyle(cfg)
    local s = cfg and cfg.kickReadyStyle
    if s == "box" or s == "border" then return s end
    return "border" -- default
end

local function _RegisterFrame(frame)
    if not frame then return end
    _registeredFrames[frame] = true
end

-- Public: create / reposition the indicator on `frame`. Called from
-- MSUF_Castbars.lua after every visuals update. Cheap, idempotent.
-- Hide all visual side-effects on a frame (used when feature off, unit out
-- of scope, no cast, or cast not interruptible). Idempotent.
local function _HideIndicator(frame)
    if not frame then return end
    if frame.kickReadyBox then frame.kickReadyBox:Hide() end
    _RestoreCastbarOutline(frame)
end

local function ApplyLayout(frame)
    if not frame or not frame.statusBar then return end

    local cfg = _GetCfg()
    if not cfg then return end

    local unit = frame.unit
    if not unit then return end

    -- Hidden cases: feature off OR unit out of scope.
    if not _AnyShowEnabled(cfg) or not _ShowOnUnit(cfg, unit) then
        _HideIndicator(frame)
        return
    end

    -- Style switching: ensure the box exists for "box" style; in "border"
    -- style we don't need the box, but creating it once is cheap and lets
    -- the user switch styles without a /reload.
    if not frame.kickReadyBox then
        frame.kickReadyBox = _CreateBox(frame)
    end
    if frame.kickReadyBox then
        _PositionBox(frame.kickReadyBox, frame, cfg)
    end

    _RegisterFrame(frame)

    -- After (re)layout, repaint to reflect current cast & cooldown state.
    if _G.MSUF_KickReady_RefreshFrame then
        _G.MSUF_KickReady_RefreshFrame(frame, nil)
    end
end

-- =============================================================================
-- Per-frame repaint (color + visibility per style) — secret-safe
-- =============================================================================

local _refreshTickerArmed = false
local _TickerStep -- forward decl

-- Single repaint entry point. Style-aware.
local function _PaintFrame(frame, readyBool)
    local cfg = _GetCfg()
    if not cfg then return end

    local style = _GetStyle(cfg)
    local readyMixin, cdMixin = _ResolveColorPair(cfg)

    -- rawNI: the secret-tagged "notInterruptible" value from the engine
    -- state (originally from UnitCastingInfo's notInterruptible field). Set
    -- in MSUF_CastbarDriver Cast() as `frame._msufApiNotInterruptibleRaw`.
    --
    -- Why we need it here:
    --   `frame.isNotInterruptible` (plain bool) is event-driven only —
    --   UNIT_SPELLCAST_NOT_INTERRUPTIBLE doesn't reliably fire for casts
    --   that are non-interruptible from the start (e.g. boss spells with
    --   permanent shield), so the upstream RefreshFrame gate doesn't catch
    --   them. The raw flag IS set at cast start but is secret-tagged, so
    --   we cannot test it in Lua. Instead we hand it to the C-side
    --   EvaluateColorFromBoolean inside _PickColor, which selects between
    --   our indicator colour and the user's outline colour without ever
    --   exposing the secret value to the Lua VM.
    local rawNI = frame._msufApiNotInterruptibleRaw

    if style == "box" then
        local box = frame.kickReadyBox
        if box and box.fill then
            -- For the box, the colour itself doesn't need the rawNI gate
            -- (we compose visibility via alpha instead). Use the cheaper
            -- single-step pick.
            local r, g, b, a = _PickColor(readyMixin, cdMixin, readyBool)
            box.fill:SetVertexColor(r, g, b, a)
            box:Show()

            -- Secret-safe visibility gate: when rawNI is true (secret or
            -- plain), alpha goes to 0 → invisible; when false, alpha 1
            -- → fully visible. The C-side helper accepts secret booleans.
            if rawNI ~= nil and box.SetAlphaFromBoolean then
                box:SetAlphaFromBoolean(rawNI, 0, 1)
            else
                box:SetAlpha(1)
            end
        end
        -- Make sure no leftover border tint from a previous style switch.
        _RestoreCastbarOutline(frame)
    else -- "border"
        if frame.kickReadyBox then frame.kickReadyBox:Hide() end

        -- For the border, we compose colour rather than alpha so the
        -- user's normal outline remains visible during non-interruptible
        -- casts (just without our tint).
        local userMixin = _GetUserOutlineMixin()
        local r, g, b, a = _PickColor(readyMixin, cdMixin, readyBool, userMixin, rawNI)
        _TintCastbarOutline(frame, r, g, b, a)
    end
end

local function RefreshFrame(frame, state)
    if not frame then return end

    local cfg = _GetCfg()
    if not cfg then _HideIndicator(frame); return end

    local unit = frame.unit
    if not unit or not _ShowOnUnit(cfg, unit) then
        _HideIndicator(frame)
        return
    end

    -- Active state from plain booleans only.
    local active = false
    if state ~= nil then
        active = (state.active == true)
    elseif frame.MSUF_castActive == true then
        active = true
    end

    if not active then
        _HideIndicator(frame)
        return
    end

    -- frame.isNotInterruptible is the cleansed plain boolean maintained by
    -- the castbar driver. It is set/cleared by UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE
    -- which deliver plain Lua booleans.
    if frame.isNotInterruptible == true then
        _HideIndicator(frame)
        return
    end

    if not _state.spellID then Resolve() end

    local readyBool = _GetReadyBoolSecret()
    _PaintFrame(frame, readyBool)

    -- Make sure the global ticker is running so the indicator repaints when
    -- the interrupt cooldown ends (SPELL_UPDATE_COOLDOWN does not always
    -- fire on the trailing edge in 12.0.5).
    if not _refreshTickerArmed and C_Timer and C_Timer.After then
        _refreshTickerArmed = true
        C_Timer.After(0.25, _TickerStep)
    end
end

-- Global low-rate repaint while at least one tracked cast is active.
function _TickerStep()
    _refreshTickerArmed = false

    local anyActive = false
    for frame in pairs(_registeredFrames) do
        if frame.MSUF_castActive == true
           and not (frame.isNotInterruptible == true) then
            local cfg = _GetCfg()
            if cfg and frame.unit and _ShowOnUnit(cfg, frame.unit) then
                local readyBool = _GetReadyBoolSecret()
                _PaintFrame(frame, readyBool)
                anyActive = true
            end
        end
    end

    if anyActive and C_Timer and C_Timer.After then
        _refreshTickerArmed = true
        C_Timer.After(0.25, _TickerStep)
    end
end

local function RefreshAll()
    for frame in pairs(_registeredFrames) do
        RefreshFrame(frame, nil)
    end
end

-- =============================================================================
-- Outline-hook: re-apply our border tint after the user's outline color is
-- (re)applied. Without this, any options-driven outline refresh would wipe
-- our green/red while a tracked cast is active.
-- =============================================================================

local _outlineHookInstalled = false
local function _InstallOutlineHook()
    if _outlineHookInstalled then return end
    if type(_G.MSUF_ApplyCastbarOutline) ~= "function" then return end
    _outlineHookInstalled = true

    -- hooksecurefunc on a global: runs after the original. The original sets
    -- the user's configured colors; we re-apply our tint on top.
    hooksecurefunc("MSUF_ApplyCastbarOutline", function(frame)
        if not frame or not _registeredFrames[frame] then return end
        if frame.MSUF_castActive ~= true then return end
        -- Plain-bool fast path: if the event-driven flag is already set,
        -- skip the C-side composition entirely — the user's colour from
        -- the original ApplyCastbarOutline call is already correct.
        if frame.isNotInterruptible == true then return end
        local cfg = _GetCfg()
        if not cfg or _GetStyle(cfg) ~= "border" then return end
        if not frame.unit or not _ShowOnUnit(cfg, frame.unit) then return end

        -- Secret-safe rawNI gate: see comment in _PaintFrame for why this
        -- is needed in addition to the plain-bool check above.
        local rawNI = frame._msufApiNotInterruptibleRaw

        local readyMixin, cdMixin = _ResolveColorPair(cfg)
        local userMixin = _GetUserOutlineMixin()
        local r, g, b, a = _PickColor(readyMixin, cdMixin, _GetReadyBoolSecret(), userMixin, rawNI)
        _TintCastbarOutline(frame, r, g, b, a)
    end)
end

-- =============================================================================
-- Event driver
-- =============================================================================

local _eventFrame = CreateFrame("Frame", "MSUF_InterruptReady_EventFrame")

local function _HandleEvent(_, event)
    if event == "PLAYER_LOGIN"
    or event == "PLAYER_ENTERING_WORLD"
    or event == "PLAYER_SPECIALIZATION_CHANGED"
    or event == "PLAYER_TALENT_UPDATE"
    or event == "ACTIVE_TALENT_GROUP_CHANGED"
    or event == "TRAIT_CONFIG_UPDATED" then
        Resolve()
        RefreshAll()
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        RefreshAll()
        return
    end
end
_eventFrame:SetScript("OnEvent", _HandleEvent)

-- Always-on events (cheap; only Resolve() runs on most of them, and only
-- once per fire — Resolve is O(1) table lookup).
_eventFrame:RegisterEvent("PLAYER_LOGIN")
_eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
_eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
_eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
_eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")

-- SPELL_UPDATE_COOLDOWN is hot. Only register it while at least one
-- castbar consumer is enabled. We re-evaluate on each Init() / config apply.
local function _ApplyEventGating()
    local cfg = _GetCfg()
    local want = _AnyShowEnabled(cfg) or (_G.MSUF_DB and _G.MSUF_DB.general
                  and _G.MSUF_DB.general.enableFocusKickIcon == true)
    if want and not _state.eventsOn then
        _eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        _state.eventsOn = true
    elseif (not want) and _state.eventsOn then
        _eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        _state.eventsOn = false
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

function _G.MSUF_KickReady_Init()
    if not _state.resolved then
        Resolve()
    end
    _ApplyEventGating()
    _EnsureColorMixins()
    _InstallOutlineHook()
end

function _G.MSUF_KickReady_GetSpellID()
    if not _state.spellID then Resolve() end
    return _state.spellID
end

function _G.MSUF_KickReady_GetSpellName()
    if not _state.spellName then Resolve() end
    return _state.spellName
end

function _G.MSUF_KickReady_GetSpellIcon()
    if not _state.iconID then Resolve() end
    return _state.iconID
end

function _G.MSUF_KickReady_IsReady()
    -- WARNING: returns a SECRET-TAINTED boolean in 12.0.5/Midnight.
    -- Callers MUST NOT use it in `if`, `==`, `~=`, `not`, or any Lua-side
    -- boolean test. Only pass it to C-side helpers:
    --   * SetAlphaFromBoolean(ready, ...)
    --   * C_CurveUtil.EvaluateColorFromBoolean(ready, mixinA, mixinB)
    -- For a Lua-safe color decision, call MSUF_KickReady_EvaluateColor(ready)
    -- and apply via :SetVertexColor(c:GetRGBA()).
    --
    -- /dump on the return value is fine — the host renderer doesn't compare.
    if not _state.spellID then Resolve() end
    return _GetReadyBoolSecret()
end

function _G.MSUF_KickReady_RefreshAll()
    _ApplyEventGating()
    RefreshAll()
end

function _G.MSUF_KickReady_RefreshFrame(frame, state)
    return RefreshFrame(frame, state)
end

function _G.MSUF_KickReady_ApplyLayout(frame)
    _ApplyEventGating()
    _InstallOutlineHook()
    return ApplyLayout(frame)
end

-- Color-pair accessor (used by FocusKickIcon overlay)
function _G.MSUF_KickReady_GetColors()
    return READY_COLOR.r,    READY_COLOR.g,    READY_COLOR.b,
           COOLDOWN_COLOR.r, COOLDOWN_COLOR.g, COOLDOWN_COLOR.b
end

-- C_CurveUtil-based color picker (secret-safe boolean -> ColorMixin)
function _G.MSUF_KickReady_EvaluateColor(readyBool)
    _EnsureColorMixins()
    if C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
    and _readyColorMixin and _cooldownColorMixin then
        return C_CurveUtil.EvaluateColorFromBoolean(readyBool, _readyColorMixin, _cooldownColorMixin)
    end
    -- Fallback: plain boolean is fine here because readyBool is already cleansed
    if readyBool == true then
        return _readyColorMixin or { GetRGBA = function() return READY_COLOR.r, READY_COLOR.g, READY_COLOR.b, 1 end }
    end
    return _cooldownColorMixin or { GetRGBA = function() return COOLDOWN_COLOR.r, COOLDOWN_COLOR.g, COOLDOWN_COLOR.b, 1 end }
end

-- Diagnostic dump — readable via /dump MSUF_KickReady_Debug()
function _G.MSUF_KickReady_Debug()
    if not _state.resolved then Resolve() end

    local id   = _state.spellID
    local nm   = _state.spellName
    local cls  = _state.classToken
    local spec = _state.specID
    local key  = spec and SPEC_OVERRIDE[spec] or "DEFAULT"

    -- Note: we deliberately do NOT call _GetReadyBoolSecret() here and
    -- include its result, because /dump renders the value via tostring() —
    -- which on some clients/dev tools may attempt comparisons internally.
    -- The taint-safe info that's actionable for diagnosis is the spell ID,
    -- spec, and event/registration state. Use the dot's visible color
    -- in-game to confirm ready/CD state.
    local frames   = 0
    for _ in pairs(_registeredFrames) do frames = frames + 1 end

    local cfg = _GetCfg() or {}
    return {
        spellID       = id,
        spellName     = nm,
        class         = cls,
        specID        = spec,
        sourceKey     = key,
        eventsOn      = _state.eventsOn,
        showTarget    = cfg.kickReadyShowTarget == true,
        showFocus     = cfg.kickReadyShowFocus  == true,
        showBoss      = cfg.kickReadyShowBoss   == true,
        size          = cfg.kickReadySize,
        anchor        = cfg.kickReadyAnchor,
        offsetX       = cfg.kickReadyOffsetX,
        offsetY       = cfg.kickReadyOffsetY,
        registered    = frames,
        focusKickIcon = (_G.MSUF_DB and _G.MSUF_DB.general
                          and _G.MSUF_DB.general.enableFocusKickIcon == true) or false,
    }
end

-- =============================================================================
-- Boot: deferred initial resolve
-- =============================================================================
-- Resolve() runs anyway on PLAYER_LOGIN; this is just for hot-reload cases
-- where the file gets loaded mid-session via /reload.
if C_Timer and C_Timer.After then
    C_Timer.After(0.1, function()
        Resolve()
        _ApplyEventGating()
    end)
end
