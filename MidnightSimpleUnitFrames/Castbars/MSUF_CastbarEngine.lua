-- Castbars/MSUF_CastbarEngine.lua
-- MSUF Castbar Engine
-- Step 3: Read-only CastState builder (no behavior change yet)
--
-- Goal (later): one unified source of truth for cast state (cast/channel/empower),
-- fill direction rules (including unifiedDirection toggle), interruptible state,
-- and update cadence.
--
-- Step 3: Provide a safe CastState builder that other modules can start using.
-- This file MUST NOT change existing runtime behavior on its own.

local addonName, ns = ...
ns = ns or {}

-- P3 Fix #16 + #10: Local FastCall cache + frame-tick BuildState cache.
local MSUF_FastCall = MSUF_FastCall or function(...) return pcall(...) end

local Registry = ns.MSUF_CastbarRegistry  -- loaded earlier in the TOC
local Style    = ns.MSUF_CastbarStyle     -- loaded earlier in the TOC

ns.MSUF_CastbarEngine = ns.MSUF_CastbarEngine or {}
local E = ns.MSUF_CastbarEngine

-- When BuildState is called multiple times for the same unit in the same game frame
-- (same GetTime() value), return the cached result instead of re-querying WoW APIs.
-- This avoids redundant UnitCastingInfo + UnitChannelInfo calls during event dispatch.
local _buildCacheTime = {}  -- unit -> GetTime() of last build

E.VERSION = 3
E._subs  = E._subs  or {}  -- key -> { callbacks }
E._state = E._state or {}  -- key -> last state


local function keyTable(k)
    if not k then return nil end
    local t = E._subs[k]
    if not t then
        t = {}
        E._subs[k] = t
    end
    return t
end

-- -------------------------------------------------
-- Public registry / subscription (kept for future steps)
-- -------------------------------------------------
function E:RegisterBar(barKey, unit, frame, styleGetter)
    if Registry and Registry.Register then
        Registry:Register(barKey, unit, frame, styleGetter)
    end
end

function E:UnregisterBar(barKey)
    if Registry and Registry.Unregister then
        Registry:Unregister(barKey)
    end
end

function E:Subscribe(key, callback)
    if not key or type(callback) ~= "function" then return end
    local t = keyTable(key)
    t[#t + 1] = callback
end

function E:Notify(key, state)
    local t = E._subs and E._subs[key]
    if not t then return end

    -- max performance: no pcall; subscribers must be safe
    for i = 1, #t do
        local cb = t[i]
        if type(cb) == "function" then
            cb(state)
        end
    end
end

function E:ForceRefresh(key)
    -- Step 3: no-op (later will rebuild state and push Apply).
end

function E:GetState(key)
    return E._state and E._state[key]
end

-- -------------------------------------------------
-- Step 3: CastState builder (read-only)
-- -------------------------------------------------
-- State fields (minimal):
--   active: boolean
--   unit: string
--   castType: "CAST" | "CHANNEL" | "EMPOWER" | nil
--   spellName, text, icon, spellId
--   durationObj (duration object when available)
--   isNotInterruptible (best-effort)
--   reverseFill (best-effort, based on DB + castType)
--
-- IMPORTANT: This does not apply anything to frames.

-- Phase 1A: Use shared _G.MSUF_EnsureDBLazy (defined in Utils, loaded earlier).
local _EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
end

local function GetFillDirectionReverseFor(castType, unit)
    _EnsureDBLazy()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local baseReverse = (g.castbarFillDirection == "RTL") and true or false
    if unit == "target" and g.castbarOpositeDirectionTarget == true then
        baseReverse = not baseReverse
    end

    local unified = (g.castbarUnifiedDirection == true)

    if castType == "CHANNEL" or castType == "EMPOWER" then
        if unified then
            return baseReverse
        end
        return not baseReverse
    end

    return baseReverse
end

local function DetectNonInterruptible(unit, frameHint)
    -- Secret-safe: never query NamePlate castbar properties (can return secret values).
    -- We only trust the MSUF castbar frame's event-driven boolean when available.
    if frameHint and frameHint.isNotInterruptible ~= nil then
        return (frameHint.isNotInterruptible == true)
    end
    return false
end

local function DetectEmpower(unit)
    -- Player-only: For target/focus/boss we intentionally do NOT attempt to detect/drive empower casts.
    -- Rationale: empower stage APIs can yield secret values and/or be unreliable for non-player units in Midnight/Beta.
    if unit ~= "player" then return false end

    -- Best-effort: if empower stage API exists and stage count > 0 while casting, treat as empower.
    if type(GetUnitEmpowerStageCount) ~= "function" then return false end

    local ok, c = MSUF_FastCall(GetUnitEmpowerStageCount, unit)

    -- Secret-safe: convert and compare only plain numbers.
    if ok then
        local n = (type(_G.MSUF__ToNumber_SecretSafe) == "function") and _G.MSUF__ToNumber_SecretSafe(c) or tonumber(c)
        if type(n) == "number" and n > 0 then
            return true
        end
    end

    return false
end

function E:BuildState(unit, frameHint)
    if not unit then return { active = false } end

    local now = GetTime()
    if _buildCacheTime[unit] == now and E._state[unit] then
        return E._state[unit]
    end
    _buildCacheTime[unit] = now

    local state = E._state[unit]
    if not state then
        state = {}
        E._state[unit] = state
    end

    -- Reset
    state.active = false
    state.unit = unit
    state.castType = "NONE"
    state.spellName = nil
    state.text = nil
    state.icon = nil
    state.spellId = nil
    state.startTimeMS = nil
    state.endTimeMS = nil
    state.durationObj = nil
	state.isNotInterruptible = false
		-- Raw API value (may be secret in Midnight/Beta). Never boolean-test/compare in Lua.
		state.apiNotInterruptible = nil
		state.apiNotInterruptibleRaw = nil
    state.reverseFill = nil

    -- Detect casting/channeling
	-- NOTE (secret-safe): notInterruptible can be a secret boolean. Only store/pass through.
	local spellName, text, icon, startTimeMS, endTimeMS, isTradeSkill, castID, apiNotInterruptible, spellId, spellSequenceID = UnitCastingInfo(unit)
    if spellName then
        -- If empowered API says we have stages while casting, classify as EMPOWER.
        local isEmpower = DetectEmpower(unit)
        state.castType = isEmpower and "EMPOWER" or "CAST"
        state.spellName = spellName
        state.text = text or spellName
        state.icon = icon
	        state.spellId = spellId
	        state.startTimeMS = startTimeMS
	        state.endTimeMS = endTimeMS
	        state.active = true
	        state.apiNotInterruptible = apiNotInterruptible
	        state.apiNotInterruptibleRaw = apiNotInterruptible
        -- Secret-safe: do not compare the API return value; it may be a "secret" boolean in Midnight/Beta.
        state.isNotInterruptible = DetectNonInterruptible(unit, frameHint)

        -- Duration object (if available)
        if type(UnitCastingDuration) == "function" then
            local ok, d = MSUF_FastCall(UnitCastingDuration, unit)
            if ok then state.durationObj = d end
        end

        state.reverseFill = GetFillDirectionReverseFor(state.castType, state.unit)
        return state
    end

    -- Channel
	-- NOTE (secret-safe): for channels, notInterruptible is returned at index 7.
	local cSpellName, cText, cIcon, cStartMS, cEndMS, cIsTradeSkill, apiNotInterruptible, cSpellId, spellSequenceID = UnitChannelInfo(unit)
    if cSpellName then
	        state.castType = "CHANNEL"
	            state.apiNotInterruptible = apiNotInterruptible
		        state.apiNotInterruptibleRaw = apiNotInterruptible
        state.spellName = cSpellName
        state.text = cText or cSpellName
        state.icon = cIcon
        state.spellId = cSpellId
        state.startTimeMS = cStartMS
        state.endTimeMS = cEndMS
        state.active = true
        -- Secret-safe: do not compare the API return value; it may be a "secret" boolean in Midnight/Beta.
        state.isNotInterruptible = DetectNonInterruptible(unit, frameHint)

        if type(UnitChannelDuration) == "function" then
            local ok, d = MSUF_FastCall(UnitChannelDuration, unit)
            if ok then state.durationObj = d end
        end

        state.reverseFill = GetFillDirectionReverseFor(state.castType, state.unit)
        return state
    end

    return state
end

-- Convenience (global) for future refactors / debugging
if not _G.MSUF_BuildCastState then
    function _G.MSUF_BuildCastState(unit, frameHint)
        return E:BuildState(unit, frameHint)
    end
end

if not _G.MSUF_GetCastbarEngine then
    _G.MSUF_GetCastbarEngine = function()
        return E
    end
end