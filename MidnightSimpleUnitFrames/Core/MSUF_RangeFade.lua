-- MSUF RangeFade v4 — Minimal C-API overhead
-- Architecture:
--   Target:
--     Friendly: UNIT_IN_RANGE_UPDATE event → 1× UnitInRange (0 polling)
--     Enemy:    1 spell registered with EnableSpellRangeCheck
--               → SPELL_RANGE_CHECK_UPDATE fires only for THAT spell (1 event/change)
--     Dead:     1 res spell registered → same mechanism
--   Focus:
--     Friendly: UNIT_IN_RANGE_UPDATE event (0 polling)
--     Enemy:    Ticker 0.5s combat / 2.0s OOC → 1× IsSpellInRange
--   Boss 1-5:
--     Ticker (shared with enemy focus) → 1× IsSpellInRange per visible boss
--     Only active during encounters.
-- Old R41z0r engine cost: 512 EnableSpellRangeCheck registrations → 100-500
-- SPELL_RANGE_CHECK_UPDATE events/sec → EventBus dispatch per event
-- New cost: 1 EnableSpellRangeCheck registration → 1 event on actual change
-- Secret-safe: IsSpellInRange NOT secret (Unhalted). Only UnitInRange +
--              CheckInteractDistance need issecretvalue guards.

_G.MSUF_RangeFadeMul = _G.MSUF_RangeFadeMul or {}
local _rfMul = _G.MSUF_RangeFadeMul

-- Shared: Spell selection + secret helpers
do
    local C_Spell = _G.C_Spell
    local C_SpellBook = _G.C_SpellBook
    local IsSpellInSpellBook = (C_SpellBook and C_SpellBook.IsSpellInSpellBook) or nil
    local EnableSpellRangeCheck = (C_Spell and C_Spell.EnableSpellRangeCheck) or nil
    local IsSpellInRange = (C_Spell and C_Spell.IsSpellInRange) or nil
    local UnitExists = _G.UnitExists
    local UnitInRange = _G.UnitInRange
    local UnitCanAttack = _G.UnitCanAttack
    local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
    local UnitIsPlayer = _G.UnitIsPlayer
    local UnitPhaseReason = _G.UnitPhaseReason
    local UnitIsConnected = _G.UnitIsConnected
    local CheckInteractDistance = _G.CheckInteractDistance
    local InCombatLockdown = _G.InCombatLockdown
    local C_Timer_After = _G.C_Timer and _G.C_Timer.After
    local issecretvalue = _G.issecretvalue

    local playerClass = select(2, _G.UnitClass("player"))

    local ENEMY_SPELLS = {
        DEATHKNIGHT={49576,47541}, DEMONHUNTER={185123,183752},
        DRUID={8921,5176}, EVOKER={362969}, HUNTER={75,466930},
        MAGE={116,133}, MONK={117952,115546}, PALADIN={20473,20271},
        PRIEST={585,8092}, ROGUE={185565,36554}, SHAMAN={188196,8042},
        WARLOCK={686,232670}, WARRIOR={355,100},
    }
    local RES_SPELLS = {
        DEATHKNIGHT={61999}, DRUID={50769,20484}, EVOKER={361227},
        MONK={115178}, PALADIN={7328,391054}, PRIEST={2006,212036},
        SHAMAN={2008}, WARLOCK={20707},
    }
    -- Friendly spells for non-party range check (IsSpellInRange fallback).
    -- 40yd heals/buffs that most specs have access to.
    local FRIENDLY_SPELLS = {
        DRUID={774,8936}, EVOKER={360823,361469}, HUNTER={34477},
        MAGE={475}, MONK={116670,115546}, PALADIN={19750,85673},
        PRIEST={17,2061}, ROGUE={57934}, SHAMAN={8004,188070},
        WARLOCK={20707}, WARRIOR={3411},
    }

    -- Target-only friendly range data mirrors UnhaltedUnitFrames Elements/Range.lua.
    local TARGET_FRIENDLY_SPELLS = {
        DEATHKNIGHT={47541},
        DEMONHUNTER={},
        DRUID={8936,774,88423,2782},
        EVOKER={361469,355913,360823},
        HUNTER={},
        MAGE={1459,475},
        MONK={116670,115450},
        PALADIN={19750,85673,4987,213644},
        PRIEST={2061,17,21562,527},
        ROGUE={57934,36554,921},
        SHAMAN={8004,188070,546},
        WARLOCK={20707,5697},
        WARRIOR={3411},
    }

    local _pEnemy, _pRes, _pFriendly = nil, nil, nil
    local _targetFriendlyActive = {}

    local function WipeTable(t)
        if wipe then
            wipe(t)
            return
        end
        for k in pairs(t) do t[k] = nil end
    end

    local function IsKnownSpell(id)
        if not id or not IsSpellInSpellBook then return false end
        return IsSpellInSpellBook(id, nil, true) == true
    end

    local function PickFirst(list)
        if not list then return nil end
        for i = 1, #list do
            if IsKnownSpell(list[i]) then return list[i] end
        end
        return nil
    end

    local function BuildActiveSpellSet(list, dest)
        WipeTable(dest)
        local first
        if not list then return nil end
        for i = 1, #list do
            local id = list[i]
            if IsKnownSpell(id) then
                dest[id] = true
                if not first then first = id end
            end
        end
        return first
    end

    local function RebuildPrimaries()
        _pEnemy    = PickFirst(ENEMY_SPELLS[playerClass])
        _pRes      = PickFirst(RES_SPELLS[playerClass])
        _pFriendly = PickFirst(FRIENDLY_SPELLS[playerClass])
        BuildActiveSpellSet(TARGET_FRIENDLY_SPELLS[playerClass], _targetFriendlyActive)
    end

    -- ══════════════════════════════════════════════════════════════
    -- Shared: State cache + apply helpers
    -- ══════════════════════════════════════════════════════════════
    local _state = {}
    local _bossUnits = { "boss1", "boss2", "boss3", "boss4", "boss5" }
    local _mulT = _G.MSUF_RangeFadeMul
    local _fastApply
    local _applyAlpha

    -- Focus/Boss rangefade must remain feature-complete by default.
    -- The lite lifecycle is now explicit opt-in only via:
    --   MSUF_DB.general.perfLiteRangeFadeFB = true
    -- This avoids silent feature regression for focus/boss range checks.
    local function UseLiteFBRuntime()
        local db = _G.MSUF_DB
        local general = db and db.general
        return (general and general.perfLiteRangeFadeFB == true) and true or false
    end

    -- Frame resolver: one canonical lookup per unit token.
    -- Target lives at _G.MSUF_target. Focus/Boss live in MSUF_UnitFrames.
    local function GetFrame(unit)
        local frames = _G.MSUF_UnitFrames
        return (frames and frames[unit]) or _G["MSUF_" .. unit]
    end

    -- ── Boss range fade: propagate alpha to castbar / aura children ──
    local _isBossUnit = { boss1=1, boss2=2, boss3=3, boss4=4, boss5=5 }

    local function PropagateBossChildren(unit, a)
        local idx = _isBossUnit[unit]
        if not idx then return end
        local db = _G.MSUF_DB
        local bossConf = db and db.boss
        if not bossConf then return end
        -- Castbar
        if bossConf.rangeFadeCastbar == true then
            local bars = _G.MSUF_BossCastbars
            local cb = bars and bars[idx]
            if cb and cb.SetAlpha then cb:SetAlpha(a) end
        end
        -- Auras
        if bossConf.rangeFadeAuras == true then
            local getAnchor = _G.MSUF_A2_GetUnitAnchor
            if type(getAnchor) == "function" then
                local anchor = getAnchor(unit)
                if anchor and anchor.SetAlpha then anchor:SetAlpha(a) end
            end
        end
    end

    local function ReapplyCurrentAlpha(f, unit, confKey)
        if not f or (f.IsForbidden and f:IsForbidden()) then return false end
        if f.IsShown and not f:IsShown() then return false end
        if not _fastApply then _fastApply = _G.MSUF_ApplyRangeFadeAlphaFast end
        local a = _mulT[unit]
        if type(a) ~= "number" then a = 1 end
        if type(_fastApply) == "function" and _fastApply(f, confKey, a) then
            return true
        end
        if not _applyAlpha then _applyAlpha = _G.MSUF_ApplyUnitAlpha end
        if type(_applyAlpha) == "function" then
            _applyAlpha(f, confKey)
            return true
        end
        return false
    end

    local function ResolveFadeAlpha(conf)
        local a = (conf and tonumber(conf.rangeFadeAlpha)) or 0.6
        -- Misc exposes this as remaining out-of-range alpha: 0% = hidden,
        -- 60% = 60% of the unitframe's normal alpha.
        if a < 0 then a = 0 elseif a > 0.6 then a = 0.6 end
        return a
    end

    local function ApplyMul(f, unit, confKey, conf, inRange)
        local prev = _state[unit]
        if inRange == prev then
            -- StatusBar:SetStatusBarColor can reset the bar texture alpha while
            -- range state is unchanged. Repair only layered frames; flat alpha
            -- is unaffected and stays on the cheap no-op path.
            if f and (f._msufAlphaBaseMode == "layered" or f._msufAlphaLayeredMode) then
                ReapplyCurrentAlpha(f, unit, confKey)
            end
            return false
        end
        _state[unit] = inRange
        local a = 1
        if inRange == false then
            a = ResolveFadeAlpha(conf)
        end
        _mulT[unit] = a
        PropagateBossChildren(unit, a)
        ReapplyCurrentAlpha(f, unit, confKey)
        return true
    end

    local function ClearMul(unit, confKey)
        local hadState = (_state[unit] ~= nil)
        local hadMul = (_mulT[unit] ~= nil and _mulT[unit] ~= 1)
        if not hadState and not hadMul then return false end
        _state[unit] = nil
        _mulT[unit] = 1
        PropagateBossChildren(unit, 1)
        local f = GetFrame(unit)
        if not f or (f.IsForbidden and f:IsForbidden()) then return true end
        if f.IsShown and not f:IsShown() then return true end
        if not _fastApply then _fastApply = _G.MSUF_ApplyRangeFadeAlphaFast end
        if type(_fastApply) == "function" and _fastApply(f, confKey, 1) then
            return true
        end
        if not _applyAlpha then _applyAlpha = _G.MSUF_ApplyUnitAlpha end
        if type(_applyAlpha) == "function" then _applyAlpha(f, confKey) end
        return true
    end

    -- ══════════════════════════════════════════════════════════════
    -- Shared: Inline range check (enemy/dead)
    -- IsSpellInRange: NOT secret (Unhalted). Direct boolean test.
    -- ══════════════════════════════════════════════════════════════
    local function CheckEnemy(unit)
        if not UnitExists(unit) then return nil end
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
            if _pRes and IsSpellInRange then
                local r = IsSpellInRange(_pRes, unit)
                if r ~= nil then return r and true or false end
            end
            return nil
        end
        if _pEnemy and IsSpellInRange then
            local r = IsSpellInRange(_pEnemy, unit)
            if r ~= nil then return r and true or false end
        end
        -- CheckInteractDistance: works on any unit, may return secret in combat
        if CheckInteractDistance then
            local ci = CheckInteractDistance(unit, 4)
            if ci ~= nil then
                if issecretvalue and issecretvalue(ci) then return nil end
                return ci and true or false
            end
        end
        return nil
    end

    -- Friendly range via UnitInRange (secret-guarded)
    -- Fallback chain for non-party friendly targets:
    --   1. UnitInRange (party/raid only — checked=true means reliable)
    --   2. IsSpellInRange with a friendly spell (works on any friendly unit)
    --   3. CheckInteractDistance (28yd, OOC only, secret-guarded)
    --   4. nil → treated as in-range (safe default)
    local function CheckFriendly(unit)
        if not UnitExists(unit) then return nil end

        -- Try UnitInRange first (works for party/raid members)
        if UnitInRange then
            local inR, checked = UnitInRange(unit)
            if issecretvalue and (issecretvalue(checked) or issecretvalue(inR)) then
                return true  -- secret → treat as in-range
            end
            if checked then return inR and true or false end
        end

        -- Fallback: IsSpellInRange with a friendly spell (NOT secret per Unhalted)
        -- Works on friendly players, but returns nil on NPCs (can't cast heals on them)
        if _pFriendly and IsSpellInRange then
            local r = IsSpellInRange(_pFriendly, unit)
            if r ~= nil then return r and true or false end
        end

        -- Fallback: CheckInteractDistance (works on ANY unit including NPCs)
        -- In combat may return secret values → secret guard handles this
        -- Index 4 = 28 yards (Follow distance)
        if CheckInteractDistance then
            local ci = CheckInteractDistance(unit, 4)
            if ci ~= nil then
                if issecretvalue and issecretvalue(ci) then return true end
                return ci and true or false
            end
        end

        return nil  -- truly indeterminate → caller treats as in-range
    end

    -- ══════════════════════════════════════════════════════════════
    -- TARGET: Event-driven with 1 registered spell (replaces R41z0r)
    -- ══════════════════════════════════════════════════════════════
    local CheckFriendlyTarget
    do
        local function NotSecret(value)
            return not (issecretvalue and issecretvalue(value))
        end

        local function TargetUnitSpellRange(unit, spells)
            if not (IsSpellInRange and spells) then return nil end
            local isNotInRange
            for spellID in pairs(spells) do
                local inRange = IsSpellInRange(spellID, unit)
                if inRange then
                    return true
                elseif inRange ~= nil then
                    isNotInRange = true
                end
            end
            if isNotInRange then return false end
        end

        local function TargetUnitInFriendlySpellsRange(unit)
            if not next(_targetFriendlyActive) then
                if CheckInteractDistance and (not InCombatLockdown or not InCombatLockdown()) then
                    return CheckInteractDistance(unit, 4)
                end
                return nil
            end

            local spellRange = TargetUnitSpellRange(unit, _targetFriendlyActive)
            if (not spellRange or spellRange == 1) and CheckInteractDistance and (not InCombatLockdown or not InCombatLockdown()) then
                local interactDistance = CheckInteractDistance(unit, 4)
                if NotSecret(interactDistance) then
                    return interactDistance
                end
                return nil
            else
                if NotSecret(spellRange) then
                    return (spellRange == nil and 1) or spellRange
                end
                return nil
            end
        end

        local function FriendlyTargetIsInRange(unit)
            if UnitIsPlayer and UnitIsPlayer(unit) and UnitPhaseReason and UnitPhaseReason(unit) then
                return false
            end

            if UnitInRange then
                local inRange, checkedRange = UnitInRange(unit)
                if NotSecret(checkedRange) and checkedRange and not inRange then
                    return false
                end
            end

            return TargetUnitInFriendlySpellsRange(unit)
        end

        CheckFriendlyTarget = function(unit)
            if not UnitExists(unit) then return nil end
            if UnitIsConnected and UnitIsConnected(unit) == false then return false end
            local inRange = FriendlyTargetIsInRange(unit)
            if inRange == nil then
                inRange = true
            end
            return (inRange == true or inRange == 1) and true or false
        end

    end

    local _targetRegisteredSpell = nil
    local _targetIsEnemy = false
    local _targetEvtFrame = nil
    local _targetDeadState = nil

    local function TargetGetConf()
        local db = _G.MSUF_DB
        local t = db and db.target
        if not t or t.rangeFadeEnabled ~= true then return nil end
        if _G.MSUF_UnitEditModeActive == true then return nil end
        return t
    end

    local function TargetUnregisterSpell()
        if _targetRegisteredSpell and EnableSpellRangeCheck then
            EnableSpellRangeCheck(_targetRegisteredSpell, false)
            _targetRegisteredSpell = nil
        end
    end

    local function TargetRegisterSpell(spellID)
        if not spellID or not EnableSpellRangeCheck then return end
        if _targetRegisteredSpell == spellID then return end
        TargetUnregisterSpell()
        _targetRegisteredSpell = spellID
        EnableSpellRangeCheck(spellID, true)
    end

    -- SPELL_RANGE_CHECK_UPDATE handler: fires ONLY for our 1 registered spell
    local function OnTargetSpellRange(event, spellIdentifier, isInRange, checksRange)
        local conf = TargetGetConf()
        if not conf then ClearMul("target", "target"); return end
        if not UnitExists("target") then ClearMul("target", "target"); return end
        -- isInRange is NOT secret (per Unhalted). Direct test.
        if checksRange then
            local result = (isInRange == true or isInRange == 1) and true or false
            ApplyMul(GetFrame("target"), "target", "target", conf, result)
        end
    end

    -- UNIT_IN_RANGE_UPDATE handler (friendly target)
    local function OnTargetFriendlyRange(_, event, arg1)
        if arg1 and arg1 ~= "target" then return end
        local conf = TargetGetConf()
        if not conf then ClearMul("target", "target"); return end
        ApplyMul(GetFrame("target"), "target", "target", conf, CheckFriendlyTarget("target"))
    end

    local function EnsureTargetEvtFrame()
        if _targetEvtFrame then return end
        _targetEvtFrame = CreateFrame("Frame")
    end

    local _targetFriendlyTicker = nil

    local function StopTargetFriendlyTicker()
        _targetFriendlyTicker = nil
    end

    local function TargetFriendlyLoopStep()
        local loop = _targetFriendlyTicker
        if not loop then return end
        local c = TargetGetConf()
        if not c or not UnitExists("target") then
            StopTargetFriendlyTicker()
            ClearMul("target", "target")
            return
        end
        ApplyMul(GetFrame("target"), "target", "target", c, CheckFriendlyTarget("target"))
        if _targetFriendlyTicker == loop and C_Timer_After then
            C_Timer_After(0.25, loop.step)
        elseif _targetFriendlyTicker == loop then
            _targetFriendlyTicker = nil
        end
    end

    local function StartTargetFriendlyLoop()
        if _targetFriendlyTicker or not C_Timer_After then return end
        local loop = {}
        loop.step = function()
            if _targetFriendlyTicker == loop then
                TargetFriendlyLoopStep()
            end
        end
        _targetFriendlyTicker = loop
        C_Timer_After(1.0, loop.step)
    end

    local function TargetClassifyAndWire()
        local conf = TargetGetConf()
        if not conf or not UnitExists("target") then
            _targetDeadState = nil
            TargetUnregisterSpell()
            StopTargetFriendlyTicker()
            ClearMul("target", "target")
            if _targetEvtFrame then
                _targetEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
                _targetEvtFrame:SetScript("OnEvent", nil)
            end
            return
        end

        -- PERF: Fast-path for party/raid members (the common case when clicking GF).
        -- UnitInRange returns (inRange, checked); checked==true means party/raid member.
        -- Skips: UnitCanAttack, UnitIsDeadOrGhost, spell registration, ticker setup.
        if UnitInRange then
            local inR, checked = UnitInRange("target")
            if not issecretvalue or not issecretvalue(checked) then
                if checked == true then
                    _targetIsEnemy = false
                    _targetDeadState = false
                    TargetUnregisterSpell()
                    EnsureTargetEvtFrame()
                    _targetEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "target")
                    _targetEvtFrame:SetScript("OnEvent", OnTargetFriendlyRange)
                    StartTargetFriendlyLoop()
                    ApplyMul(GetFrame("target"), "target", "target", conf, CheckFriendlyTarget("target"))
                    return
                end
            end
        end

        EnsureTargetEvtFrame()
        _targetIsEnemy = (UnitCanAttack and UnitCanAttack("player", "target")) and true or false
        _targetDeadState = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("target")) and true or false

        if _targetIsEnemy then
            -- Enemy: register 1 spell for SPELL_RANGE_CHECK_UPDATE
            _targetEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
            StopTargetFriendlyTicker()
            local spell = _pEnemy
            if _targetDeadState then spell = _pRes end
            if spell then
                TargetRegisterSpell(spell)
            else
                TargetUnregisterSpell()
            end
            -- Also do an immediate check
            ApplyMul(GetFrame("target"), "target", "target", conf, CheckEnemy("target"))
        else
            -- Friendly path
            TargetUnregisterSpell()

            -- Check if target is a party/raid member (UnitInRange works → event-driven)
            local isPartyMember = false
            if UnitInRange then
                local _, checked = UnitInRange("target")
                if not issecretvalue or not issecretvalue(checked) then
                    isPartyMember = (checked == true)
                end
            end

            if isPartyMember then
                -- Party member: UNIT_IN_RANGE_UPDATE fires reliably
                _targetEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "target")
                _targetEvtFrame:SetScript("OnEvent", OnTargetFriendlyRange)
                StartTargetFriendlyLoop()
            else
                -- Non-party friendly (NPC, non-group player):
                -- UNIT_IN_RANGE_UPDATE won't fire. Use target-only ticker with
                -- IsSpellInRange / CheckInteractDistance fallback.
                _targetEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
                _targetEvtFrame:SetScript("OnEvent", nil)
                StopTargetFriendlyTicker()
                StartTargetFriendlyLoop()
            end

            -- Immediate check
            ApplyMul(GetFrame("target"), "target", "target", conf, CheckFriendlyTarget("target"))
        end
    end

    -- ══════════════════════════════════════════════════════════════
    -- Target: Global event wiring
    -- ══════════════════════════════════════════════════════════════
    local _targetWired = false

    local function WireTargetEvents()
        if _targetWired then return end; _targetWired = true
        local bus = _G.MSUF_EventBus_Register
        if type(bus) ~= "function" then return end

        -- 1 event for our 1 registered spell (was: 100-500 events for 512 spells)
        bus("SPELL_RANGE_CHECK_UPDATE", "MSUF_RANGEFADE", function(event, spellIdentifier, isInRange, checksRange)
            if _targetIsEnemy then
                OnTargetSpellRange(event, spellIdentifier, isInRange, checksRange)
            end
        end)

        do
            local _qRF
            local function _flushRF() _qRF = nil; _state["target"] = nil; TargetClassifyAndWire() end
            bus("PLAYER_TARGET_CHANGED", "MSUF_RANGEFADE", function()
                if not _qRF then _qRF = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("RANGEFADE_TARGET_CHANGED", _flushRF) else C_Timer.After(0, _flushRF) end end
            end)
        end
        bus("PLAYER_ENTERING_WORLD", "MSUF_RANGEFADE", function()
            RebuildPrimaries()
            _state["target"] = nil
            TargetClassifyAndWire()
        end)
        bus("UNIT_FLAGS", "MSUF_RANGEFADE", function(_, unit)
            if unit ~= "target" then return end
            if not UnitExists("target") then
                if _targetDeadState ~= nil then
                    _targetDeadState = nil
                    _state["target"] = nil
                    TargetClassifyAndWire()
                end
                return
            end
            local isDead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("target")) and true or false
            if isDead ~= _targetDeadState then
                _targetDeadState = isDead
                _state["target"] = nil
                TargetClassifyAndWire()
            end
        end)
        -- SPELLS_CHANGED coalescing: can fire 800+/sec in combat.
        -- Defer to next frame to process once regardless of fire count.
        local _tgtSpellsDirty = false
        local function _FlushTargetSpellsChanged()
            _tgtSpellsDirty = false
            RebuildPrimaries()
            if _targetIsEnemy and UnitExists("target") then
                local spell = _pEnemy
                if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then spell = _pRes end
                if spell ~= _targetRegisteredSpell then
                    TargetRegisterSpell(spell)
                end
            elseif UnitExists("target") then
                local conf = TargetGetConf()
                if conf then
                    ApplyMul(GetFrame("target"), "target", "target", conf, CheckFriendlyTarget("target"))
                end
            end
        end
        bus("SPELLS_CHANGED", "MSUF_RANGEFADE", function()
            if _tgtSpellsDirty then return end
            _tgtSpellsDirty = true
            if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("RANGEFADE_SPELLS_CHANGED", _FlushTargetSpellsChanged) elseif C_Timer_After then C_Timer_After(0, _FlushTargetSpellsChanged) else _FlushTargetSpellsChanged() end
        end)
        bus("PLAYER_TALENT_UPDATE", "MSUF_RANGEFADE", function()
            RebuildPrimaries()
            if UnitExists("target") then
                TargetClassifyAndWire()
            end
        end)
        bus("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "MSUF_RANGEFADE", function()
            RebuildPrimaries()
            if UnitExists("target") then
                TargetClassifyAndWire()
            end
        end)
        bus("TRAIT_CONFIG_UPDATED", "MSUF_RANGEFADE", function()
            RebuildPrimaries()
            if UnitExists("target") then
                TargetClassifyAndWire()
            end
        end)
    end

    local function UnwireTargetEvents()
        if not _targetWired then return end; _targetWired = false
        local unreg = _G.MSUF_EventBus_Unregister
        if type(unreg) ~= "function" then return end
        unreg("SPELL_RANGE_CHECK_UPDATE", "MSUF_RANGEFADE")
        unreg("PLAYER_TARGET_CHANGED", "MSUF_RANGEFADE")
        unreg("PLAYER_ENTERING_WORLD", "MSUF_RANGEFADE")
        unreg("UNIT_FLAGS", "MSUF_RANGEFADE")
        unreg("SPELLS_CHANGED", "MSUF_RANGEFADE")
        unreg("PLAYER_TALENT_UPDATE", "MSUF_RANGEFADE")
        unreg("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "MSUF_RANGEFADE")
        unreg("TRAIT_CONFIG_UPDATED", "MSUF_RANGEFADE")
    end

    -- Public target API (signatures preserved)
    function _G.MSUF_RangeFade_Register(getConfigFn, applyAlphaFn, opts)
        -- Legacy compat: getConfigFn/applyAlphaFn are no longer used.
        -- Target now reads DB directly + uses ApplyMul.
    end

    function _G.MSUF_RangeFade_RebuildSpells()
        RebuildPrimaries()
        TargetClassifyAndWire()
    end

    function _G.MSUF_RangeFade_OnEvent_SpellRangeUpdate(spellIdentifier, isInRange, checksRange)
        -- Handled internally via EventBus now
    end

    function _G.MSUF_RangeFade_ApplyCurrent(force)
        local conf = TargetGetConf()
        if conf and UnitExists("target") then
            if _targetIsEnemy then
                ApplyMul(GetFrame("target"), "target", "target", conf, CheckEnemy("target"))
            else
                ApplyMul(GetFrame("target"), "target", "target", conf, CheckFriendlyTarget("target"))
            end
        end
    end

    function _G.MSUF_RangeFade_Reset()
        _state["target"] = nil
        _mulT.target = 1
        StopTargetFriendlyTicker()
        -- Re-apply on next target event
    end

    function _G.MSUF_RangeFade_Shutdown()
        TargetUnregisterSpell()
        StopTargetFriendlyTicker()
        UnwireTargetEvents()
        ClearMul("target", "target")
        if _targetEvtFrame then
            _targetEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
            _targetEvtFrame:SetScript("OnEvent", nil)
        end
    end

    function _G.MSUF_RangeFade_EvaluateActive(force)
        local db = _G.MSUF_DB
        local t = db and db.target
        local want = (t and t.rangeFadeEnabled == true)
        if _G.MSUF_UnitEditModeActive == true then want = false end
        if want then
            RebuildPrimaries()
            WireTargetEvents()
            TargetClassifyAndWire()
        else
            TargetUnregisterSpell()
            StopTargetFriendlyTicker()
            UnwireTargetEvents()
            ClearMul("target", "target")
        end
    end

    -- Backwards compat
    function _G.MSUF_RangeFade_Rebuild()
        _G.MSUF_RangeFade_RebuildSpells()
    end

    -- ══════════════════════════════════════════════════════════════
    -- ══════════════════════════════════════════════════════════════
    -- FOCUS/BOSS: Smart-sleep ticker + event-driven friendly focus
    -- Ticker lifecycle (SyncTicker):
    --   RUNNING when: enemy focus OR boss range enabled → 0.50s combat / 2.0s OOC
    --   SLEEPING when: only friendly focus (event-driven) → 0 CPU
    --   STOPPED when: no focus + no boss enabled → 0 CPU
    -- Friendly focus: UNIT_IN_RANGE_UPDATE (oUF approach, 0 polling always)
    -- Unit swaps: immediate check via events, then SyncTicker re-evaluates
    -- Burst mode: 0.20s for a short window after focus/boss state changes
    -- ══════════════════════════════════════════════════════════════
    local _focusIsEnemy = false
    local _focusEvtFrame = nil
    local _ticker = nil
    local _tickRate = 0
    local _playerMoving = false
    local _TICK_COMBAT = 0.50
    local _TICK_OOC = 2.0
    local _TICK_COMBAT_FOCUS = 0.14
    local _TICK_COMBAT_BOSS = 0.12
    local _TICK_MOVING_FOCUS = 0.10
    local _TICK_MOVING_BOSS = 0.08
    local _TICK_OOC_FOCUS = 0.35
    local _TICK_OOC_BOSS = 0.22
    local _TICK_BURST = 0.05
    local _BURST_DURATION = 0.75
    local _burstSerial = 0
    local HasActiveEnemyFocusRangeUnit, HasActiveBossRangeUnit, NeedsPoll, RequestBurst
    local _pollUnits, _pollConfKey, _pollFrames, _pollCount = {}, {}, {}, 0

    local function OnFocusFriendlyRange(_, event, arg1)
        if arg1 and arg1 ~= "focus" then return end
        local db = _G.MSUF_DB
        local conf = db and db.focus
        if not conf or conf.rangeFadeEnabled ~= true then ClearMul("focus", "focus"); return end
        if _G.MSUF_UnitEditModeActive == true then ClearMul("focus", "focus"); return end
        ApplyMul(GetFrame("focus"), "focus", "focus", conf, CheckFriendly("focus"))
    end

    local function EnsureFocusEvtFrame()
        if _focusEvtFrame then return end
        _focusEvtFrame = CreateFrame("Frame")
        _focusEvtFrame:SetScript("OnEvent", OnFocusFriendlyRange)
    end

    local function StopTicker()
        _ticker = nil
        _tickRate = 0
        _burstSerial = _burstSerial + 1
    end

    local function RebuildPollList()
        _pollCount = 0
        if _G.MSUF_UnitEditModeActive == true then return end

        local db = _G.MSUF_DB
        local focusConf = db and db.focus
        if _focusIsEnemy and focusConf and focusConf.rangeFadeEnabled == true then
            local f = GetFrame("focus")
            if UnitExists and UnitExists("focus") and (not f or not f.IsShown or f:IsShown()) then
                _pollCount = _pollCount + 1
                _pollUnits[_pollCount] = "focus"
                _pollConfKey[_pollCount] = "focus"
                _pollFrames[_pollCount] = f
            end
        end

        local bossConf = db and db.boss
        if bossConf and bossConf.rangeFadeEnabled == true then
            local frames = _G.MSUF_UnitFrames
            for i = 1, 5 do
                local unit = _bossUnits[i]
                local f = frames and frames[unit]
                if f and f.IsShown and f:IsShown() and UnitExists(unit) then
                    _pollCount = _pollCount + 1
                    _pollUnits[_pollCount] = unit
                    _pollConfKey[_pollCount] = "boss"
                    _pollFrames[_pollCount] = f
                end
            end
        end
    end

    local function CheckEnemyUnits()
        if _pollCount <= 0 then
            RebuildPollList()
            if _pollCount <= 0 then
                StopTicker()
                return
            end
        end

        local db = _G.MSUF_DB
        local focusConf = db and db.focus
        local bossConf = db and db.boss
        local changedAny = false

        for i = 1, _pollCount do
            local unit = _pollUnits[i]
            local confKey = _pollConfKey[i]
            local conf = (confKey == "focus") and focusConf or bossConf
            -- PERF: cached frame ref (populated in RebuildPollList). Eliminates
            -- GetFrame(unit) hash lookup per poll tick. During burst (20/s × up
            -- to 6 units = 120 lookups/s) this is meaningful.
            local f = _pollFrames[i]
            if conf and f and (not f.IsShown or f:IsShown()) and UnitExists(unit) then
                if ApplyMul(f, unit, confKey, conf, CheckEnemy(unit)) then
                    changedAny = true
                end
            else
                if ClearMul(unit, confKey) then
                    changedAny = true
                end
            end
        end

        if changedAny and _tickRate > _TICK_BURST and C_Timer_After then
            C_Timer_After(0, function()
                if NeedsPoll() then
                    RequestBurst(0.25)
                end
            end)
        end
    end

    function HasActiveEnemyFocusRangeUnit()
        if _G.MSUF_UnitEditModeActive == true then return false end
        local db = _G.MSUF_DB
        local conf = db and db.focus
        if not conf or conf.rangeFadeEnabled ~= true then return false end
        if not _focusIsEnemy then return false end
        if not UnitExists or not UnitExists("focus") then return false end
        local f = GetFrame("focus")
        if f and f.IsShown and not f:IsShown() then return false end
        return true
    end

    local function DesiredRate()
        local hasBoss = HasActiveBossRangeUnit()
        local hasEnemyFocus = HasActiveEnemyFocusRangeUnit()
        local inCombat = (_G.MSUF_InCombat == true)

        if _playerMoving then
            if hasBoss then return _TICK_MOVING_BOSS end
            if hasEnemyFocus then return _TICK_MOVING_FOCUS end
        end

        if inCombat then
            if hasBoss then return _TICK_COMBAT_BOSS end
            if hasEnemyFocus then return _TICK_COMBAT_FOCUS end
            return _TICK_COMBAT
        end

        if hasBoss then return _TICK_OOC_BOSS end
        if hasEnemyFocus then return _TICK_OOC_FOCUS end
        return _TICK_OOC
    end

    local ScheduleTickerStep
    local function RangeFadeTickerLoopStep()
        local loop = _ticker
        if not loop then return end
        CheckEnemyUnits()
        if _ticker == loop then
            ScheduleTickerStep(loop)
        end
    end

    ScheduleTickerStep = function(loop)
        if not C_Timer_After then
            StopTicker()
            return
        end
        C_Timer_After(_tickRate, loop.step)
    end

    local function EnsureTicker(rate)
        if not C_Timer_After then return end
        if _ticker and _tickRate == rate then return end
        _burstSerial = _burstSerial + 1
        _tickRate = rate
        local loop = {}
        loop.step = function()
            if _ticker == loop then
                RangeFadeTickerLoopStep()
            end
        end
        _ticker = loop
        ScheduleTickerStep(loop)
    end

    function HasActiveBossRangeUnit()
        local frames = _G.MSUF_UnitFrames
        for i = 1, 5 do
            local unit = _bossUnits[i]
            local f = frames and frames[unit]
            if f and f.IsShown and f:IsShown() and UnitExists(unit) then
                return true
            end
        end
        return false
    end

    -- Smart-sleep: only run ticker when enemy units need polling.
    -- Friendly focus = event-driven → no ticker needed.
    function NeedsPoll()
        if _G.MSUF_UnitEditModeActive == true then return false end
        if _pollCount > 0 then return true end
        if HasActiveEnemyFocusRangeUnit() then return true end
        local db = _G.MSUF_DB
        local bossConf = db and db.boss
        if bossConf and bossConf.rangeFadeEnabled == true and HasActiveBossRangeUnit() then return true end
        return false
    end

    local function SyncTicker()
        RebuildPollList()
        if _pollCount > 0 then
            EnsureTicker(DesiredRate())
        else
            StopTicker()
        end
    end

    function RequestBurst(duration)
        if _G.MSUF_UnitEditModeActive == true then return end
        if not NeedsPoll() then return end
        duration = tonumber(duration) or _BURST_DURATION
        if duration < 0.20 then duration = 0.20 end
        EnsureTicker(_TICK_BURST)
        if not C_Timer_After then return end
        _burstSerial = _burstSerial + 1
        local serial = _burstSerial
        C_Timer_After(duration, function()
            if serial ~= _burstSerial then return end
            SyncTicker()
        end)
    end

    local function IsTrackedFBUnit(unit)
        local db = _G.MSUF_DB
        local focusOn = db and db.focus and db.focus.rangeFadeEnabled == true and not UseLiteFBRuntime()
        local bossOn  = db and db.boss  and db.boss.rangeFadeEnabled  == true and not UseLiteFBRuntime()
        if unit == "focus" then return focusOn and true or false end
        if unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5" then
            return bossOn and true or false
        end
        return false
    end

    local function RangeFadeFBWanted()
        if UseLiteFBRuntime() then return false end
        local db = _G.MSUF_DB
        if db and db.focus and db.focus.rangeFadeEnabled == true then return true end
        if db and db.boss  and db.boss.rangeFadeEnabled  == true then return true end
        return false
    end

    local function ClassifyFocus()
        if not UnitExists or not UnitExists("focus") then _focusIsEnemy = false; return end
        _focusIsEnemy = (UnitCanAttack and UnitCanAttack("player", "focus")) and true or false
    end

    local _fbEvtFrame = nil
    local _fbEvents = {}
    local _fbSpellsDirty = false
    local function EnsureFBEventFrame()
        if _fbEvtFrame then return _fbEvtFrame end
        local ef = CreateFrame("Frame")
        ef:SetScript("OnEvent", function(_, event, arg1)
            if event == "PLAYER_REGEN_DISABLED" then
                if not NeedsPoll() and not _ticker then return end
                SyncTicker()
                if NeedsPoll() or _ticker then
                    CheckEnemyUnits()
                end
            elseif event == "PLAYER_REGEN_ENABLED" then
                if not NeedsPoll() and not _ticker then return end
                SyncTicker()
                if NeedsPoll() or _ticker then
                    CheckEnemyUnits()
                end
            elseif event == "PLAYER_STARTED_MOVING" then
                if not NeedsPoll() and not _ticker then return end
                _playerMoving = true
                SyncTicker()
                if NeedsPoll() then
                    RequestBurst(0.60)
                    CheckEnemyUnits()
                end
            elseif event == "PLAYER_STOPPED_MOVING" then
                if not NeedsPoll() and not _ticker then return end
                _playerMoving = false
                SyncTicker()
                if NeedsPoll() or _ticker then
                    CheckEnemyUnits()
                end
            elseif event == "PLAYER_FOCUS_CHANGED" then
                _state["focus"] = nil
                ClassifyFocus()
                if UnitExists("focus") and not _focusIsEnemy then
                    EnsureFocusEvtFrame()
                    _focusEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "focus")
                    OnFocusFriendlyRange(nil, event, "focus")
                else
                    if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
                    if not UnitExists("focus") then
                        ClearMul("focus", "focus")
                    end
                end
                SyncTicker()
                if NeedsPoll() then
                    RequestBurst(_BURST_DURATION)
                    CheckEnemyUnits()
                end
            elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
                for i = 1, 5 do _state[_bossUnits[i]] = nil end
                SyncTicker()
                if NeedsPoll() then
                    RequestBurst(_BURST_DURATION)
                    CheckEnemyUnits()
                end
            elseif event == "UNIT_FLAGS" or event == "UNIT_CONNECTION"
                or event == "UNIT_PHASE" or event == "UNIT_TARGETABLE_CHANGED"
                or event == "UNIT_FACTION" then
                local unit = arg1
                if not IsTrackedFBUnit(unit) then return end
                _state[unit] = nil
                if unit == "focus" then
                    ClassifyFocus()
                    if UnitExists("focus") and not _focusIsEnemy then
                        EnsureFocusEvtFrame()
                        _focusEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "focus")
                        OnFocusFriendlyRange(nil, event, "focus")
                        SyncTicker()
                        return
                    else
                        if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
                        if not UnitExists("focus") then
                            ClearMul("focus", "focus")
                        end
                    end
                end
                SyncTicker()
                if NeedsPoll() then
                    RequestBurst(0.80)
                    CheckEnemyUnits()
                elseif unit ~= "focus" then
                    ClearMul(unit, "boss")
                end
            elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
                or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED"
                or event == "PLAYER_ENTERING_WORLD" then
                -- Rare events: process immediately
                if event == "PLAYER_ENTERING_WORLD" then
                    _playerMoving = false
                end
                RebuildPrimaries()
                for k in pairs(_state) do _state[k] = nil end
                SyncTicker()
                if NeedsPoll() or _ticker then
                    if NeedsPoll() then
                        RequestBurst(0.80)
                    end
                    CheckEnemyUnits()
                end
            elseif event == "SPELLS_CHANGED" then
                -- SPELLS_CHANGED coalescing: can fire 800+/sec in combat.
                -- Defer to next frame to process once.
                if not _fbSpellsDirty then
                    _fbSpellsDirty = true
                    if C_Timer_After then
                        C_Timer_After(0, function()
                            _fbSpellsDirty = false
                            RebuildPrimaries()
                            for k in pairs(_state) do _state[k] = nil end
                            SyncTicker()
                            if NeedsPoll() or _ticker then
                                if NeedsPoll() then RequestBurst(0.80) end
                                CheckEnemyUnits()
                            end
                        end)
                    else
                        _fbSpellsDirty = false
                        RebuildPrimaries()
                        for k in pairs(_state) do _state[k] = nil end
                        SyncTicker()
                    end
                end
            end
        end)
        _fbEvtFrame = ef
        return ef
    end

    local function SetFBEvent(event, want)
        local ef = EnsureFBEventFrame()
        if want then
            if not _fbEvents[event] then
                ef:RegisterEvent(event)
                _fbEvents[event] = true
            end
        elseif _fbEvents[event] then
            ef:UnregisterEvent(event)
            _fbEvents[event] = nil
        end
    end

    local function SetFBUnitEvent(event, focusOn, bossOn)
        local ef = EnsureFBEventFrame()
        local mask = (focusOn and 1 or 0) + (bossOn and 2 or 0)
        if mask == 0 then
            if _fbEvents[event] then
                ef:UnregisterEvent(event)
                _fbEvents[event] = nil
            end
            return
        end
        if _fbEvents[event] == mask then return end
        if _fbEvents[event] then ef:UnregisterEvent(event) end

        local ok = false
        if ef.RegisterUnitEvent then
            if mask == 3 then
                ok = pcall(ef.RegisterUnitEvent, ef, event, "focus", "boss1", "boss2", "boss3", "boss4", "boss5")
            elseif focusOn then
                ok = pcall(ef.RegisterUnitEvent, ef, event, "focus")
            else
                ok = pcall(ef.RegisterUnitEvent, ef, event, "boss1", "boss2", "boss3", "boss4", "boss5")
            end
        end
        if not ok then ef:RegisterEvent(event) end
        _fbEvents[event] = mask
    end

    local function RefreshFBEventLifecycle()
        local db = _G.MSUF_DB
        local focusOn = db and db.focus and db.focus.rangeFadeEnabled == true and not UseLiteFBRuntime()
        local bossOn  = db and db.boss  and db.boss.rangeFadeEnabled  == true and not UseLiteFBRuntime()

        if not focusOn and not bossOn then
            if _fbEvtFrame then
                _fbEvtFrame:UnregisterAllEvents()
            end
            for k in pairs(_fbEvents) do _fbEvents[k] = nil end
            return false, false
        end

        -- shared polling/reactivity events only when at least one FB feature is on
        SetFBEvent("PLAYER_REGEN_DISABLED", true)
        SetFBEvent("PLAYER_REGEN_ENABLED", true)
        SetFBEvent("PLAYER_STARTED_MOVING", true)
        SetFBEvent("PLAYER_STOPPED_MOVING", true)
        SetFBEvent("SPELLS_CHANGED", true)
        SetFBEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", true)
        SetFBEvent("PLAYER_TALENT_UPDATE", true)
        SetFBEvent("TRAIT_CONFIG_UPDATED", true)
        SetFBEvent("PLAYER_ENTERING_WORLD", true)
        SetFBUnitEvent("UNIT_FLAGS", focusOn, bossOn)
        SetFBUnitEvent("UNIT_CONNECTION", focusOn, bossOn)
        SetFBUnitEvent("UNIT_PHASE", focusOn, bossOn)
        SetFBUnitEvent("UNIT_TARGETABLE_CHANGED", focusOn, bossOn)
        SetFBUnitEvent("UNIT_FACTION", focusOn, bossOn)

        -- focus-only lifecycle
        SetFBEvent("PLAYER_FOCUS_CHANGED", focusOn)

        -- boss-only lifecycle
        SetFBEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", bossOn)

        return focusOn, bossOn
    end

    function _G.MSUF_RangeFadeFB_RebuildSpells()
        if RangeFadeFBWanted() ~= true then return end
        RebuildPrimaries()
    end

    function _G.MSUF_RangeFadeFB_Reset()
        for k in pairs(_state) do _state[k] = nil end
        _pollCount = 0
        _mulT.focus = 1
        for i = 1, 5 do _mulT[_bossUnits[i]] = 1 end
    end

    function _G.MSUF_RangeFadeFB_EvaluateActive(force)
        local focusOn, bossOn = RefreshFBEventLifecycle()
        if focusOn or bossOn then
            if force == true then for k in pairs(_state) do _state[k] = nil end end
            RebuildPrimaries()
            if focusOn then
                ClassifyFocus()
                -- Friendly focus: event-driven
                if UnitExists and UnitExists("focus") and not _focusIsEnemy then
                    EnsureFocusEvtFrame()
                    _focusEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "focus")
                    OnFocusFriendlyRange(nil, "INIT", "focus")
                else
                    if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
                end
            else
                _focusIsEnemy = false
                if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
                ClearMul("focus", "focus")
            end
            if not bossOn then
                for i = 1, 5 do ClearMul(_bossUnits[i], "boss") end
            end
            -- Ticker: only when enemy units need polling (smart-sleep)
            SyncTicker()
            CheckEnemyUnits()
            return
        end
        -- Fully shut down focus/boss rangefade lifecycle when both features are off.
        _playerMoving = false
        StopTicker()
        _focusIsEnemy = false
        if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
        ClearMul("focus", "focus")
        for i = 1, 5 do ClearMul(_bossUnits[i], "boss") end
    end

    function _G.MSUF_RangeFadeFB_ApplyCurrent(force)
        _G.MSUF_RangeFadeFB_EvaluateActive(force)
    end

    -- ══════════════════════════════════════════════════════════════
    -- InitPostLogin: called once after unitframes exist
    -- ══════════════════════════════════════════════════════════════
    function _G.MSUF_RangeFade_InitPostLogin()
        RebuildPrimaries()

        -- Target: evaluate via EvaluateActive (wires events + registers 1 spell)
        if C_Timer_After then
            C_Timer_After(0, function()
                if _G.MSUF_RangeFade_EvaluateActive then
                    _G.MSUF_RangeFade_EvaluateActive(true)
                end
            end)
        elseif _G.MSUF_RangeFade_EvaluateActive then
            _G.MSUF_RangeFade_EvaluateActive(true)
        end

        -- Focus/Boss: evaluate active
        _G.MSUF_RangeFadeFB_EvaluateActive(true)
    end
end
