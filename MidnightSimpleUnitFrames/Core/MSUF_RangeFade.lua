-- ============================================================================
-- MSUF RangeFade v4 — Minimal C-API overhead
--
-- Architecture:
--   Target:
--     Friendly: UNIT_IN_RANGE_UPDATE event → 1× UnitInRange (0 polling)
--     Enemy:    1 spell registered with EnableSpellRangeCheck
--               → SPELL_RANGE_CHECK_UPDATE fires only for THAT spell (1 event/change)
--     Dead:     1 res spell registered → same mechanism
--
--   Focus:
--     Friendly: UNIT_IN_RANGE_UPDATE event (0 polling)
--     Enemy:    Ticker 0.5s combat / 2.0s OOC → 1× IsSpellInRange
--
--   Boss 1-5:
--     Ticker (shared with enemy focus) → 1× IsSpellInRange per visible boss
--     Only active during encounters.
--
-- Old R41z0r engine cost: 512 EnableSpellRangeCheck registrations → 100-500
-- SPELL_RANGE_CHECK_UPDATE events/sec → EventBus dispatch per event
--
-- New cost: 1 EnableSpellRangeCheck registration → 1 event on actual change
--
-- Secret-safe: IsSpellInRange NOT secret (Unhalted). Only UnitInRange +
--              CheckInteractDistance need issecretvalue guards.
-- ============================================================================

_G.MSUF_RangeFadeMul = _G.MSUF_RangeFadeMul or {}

function _G.MSUF_GetRangeFadeMul(key, unit, frame)
    local t = _G.MSUF_RangeFadeMul
    if not t then return 1 end
    local v = t[key]
    if type(v) == "number" then return v end
    if unit then
        v = t[unit]
        if type(v) == "number" then return v end
    end
    return 1
end

-- ============================================================================
-- Shared: Spell selection + secret helpers
-- ============================================================================
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
    local CheckInteractDistance = _G.CheckInteractDistance
    local C_Timer_NewTicker = _G.C_Timer and _G.C_Timer.NewTicker
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

    local _pEnemy, _pRes = nil, nil

    local function PickFirst(list)
        if not list or not IsSpellInSpellBook then return nil end
        for i = 1, #list do
            if list[i] and IsSpellInSpellBook(list[i], nil, true) then return list[i] end
        end
        return nil
    end

    local function RebuildPrimaries()
        _pEnemy = PickFirst(ENEMY_SPELLS[playerClass])
        _pRes   = PickFirst(RES_SPELLS[playerClass])
    end

    -- ══════════════════════════════════════════════════════════════
    -- Shared: State cache + apply helpers
    -- ══════════════════════════════════════════════════════════════
    local _state = {}
    local _bossUnits = { "boss1", "boss2", "boss3", "boss4", "boss5" }

    local function ApplyMul(unit, confKey, conf, inRange)
        local prev = _state[unit]
        if inRange == prev then return end
        _state[unit] = inRange
        local mulT = _G.MSUF_RangeFadeMul
        if type(mulT) ~= "table" then mulT = {}; _G.MSUF_RangeFadeMul = mulT end
        local a = 1
        if inRange == false then
            a = (conf and tonumber(conf.rangeFadeAlpha)) or 0.5
            if a < 0 then a = 0 elseif a > 1 then a = 1 end
        end
        mulT[unit] = a
        local frames = _G.MSUF_UnitFrames
        local f = frames and frames[unit]
        if not f or (f.IsForbidden and f:IsForbidden()) then return end
        if f.IsShown and not f:IsShown() then return end
        local apply = _G.MSUF_ApplyUnitAlpha
        if type(apply) == "function" then apply(f, confKey) end
    end

    local function ClearMul(unit, confKey)
        if _state[unit] == nil then return end
        _state[unit] = nil
        local mulT = _G.MSUF_RangeFadeMul
        if type(mulT) ~= "table" then return end
        if mulT[unit] == 1 or mulT[unit] == nil then return end
        mulT[unit] = 1
        local frames = _G.MSUF_UnitFrames
        local f = frames and frames[unit]
        if not f or (f.IsForbidden and f:IsForbidden()) then return end
        local apply = _G.MSUF_ApplyUnitAlpha
        if type(apply) == "function" then apply(f, confKey) end
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
        if _G.MSUF_InCombat ~= true and CheckInteractDistance then
            local ci = CheckInteractDistance(unit, 4)
            if not issecretvalue or not issecretvalue(ci) then return ci end
        end
        return nil
    end

    -- Friendly range via UnitInRange (secret-guarded)
    local function CheckFriendly(unit)
        if not UnitExists(unit) then return nil end
        if not UnitInRange then return nil end
        local inR, checked = UnitInRange(unit)
        if issecretvalue and (issecretvalue(checked) or issecretvalue(inR)) then
            return true  -- secret → treat as in-range
        end
        if checked then return inR and true or false end
        return true  -- not in group → treat as in-range
    end

    -- ══════════════════════════════════════════════════════════════
    -- TARGET: Event-driven with 1 registered spell (replaces R41z0r)
    -- ══════════════════════════════════════════════════════════════
    local _targetRegisteredSpell = nil
    local _targetIsEnemy = false
    local _targetEvtFrame = nil

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
            ApplyMul("target", "target", conf, result)
        end
    end

    -- UNIT_IN_RANGE_UPDATE handler (friendly target)
    local function OnTargetFriendlyRange(_, event, arg1)
        if arg1 and arg1 ~= "target" then return end
        local conf = TargetGetConf()
        if not conf then ClearMul("target", "target"); return end
        ApplyMul("target", "target", conf, CheckFriendly("target"))
    end

    local function EnsureTargetEvtFrame()
        if _targetEvtFrame then return end
        _targetEvtFrame = CreateFrame("Frame")
    end

    local function TargetClassifyAndWire()
        local conf = TargetGetConf()
        if not conf or not UnitExists("target") then
            TargetUnregisterSpell()
            ClearMul("target", "target")
            if _targetEvtFrame then
                _targetEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
                _targetEvtFrame:SetScript("OnEvent", nil)
            end
            return
        end

        EnsureTargetEvtFrame()
        _targetIsEnemy = (UnitCanAttack and UnitCanAttack("player", "target")) and true or false

        if _targetIsEnemy then
            -- Enemy: register 1 spell for SPELL_RANGE_CHECK_UPDATE
            _targetEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
            local spell = _pEnemy
            if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then spell = _pRes end
            if spell then
                TargetRegisterSpell(spell)
            end
            -- Also do an immediate check
            ApplyMul("target", "target", conf, CheckEnemy("target"))
        else
            -- Friendly: UNIT_IN_RANGE_UPDATE (zero polling)
            TargetUnregisterSpell()
            _targetEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "target")
            _targetEvtFrame:SetScript("OnEvent", OnTargetFriendlyRange)
            ApplyMul("target", "target", conf, CheckFriendly("target"))
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

        bus("PLAYER_TARGET_CHANGED", "MSUF_RANGEFADE", function()
            _state["target"] = nil
            TargetClassifyAndWire()
        end)
        bus("PLAYER_ENTERING_WORLD", "MSUF_RANGEFADE", function()
            RebuildPrimaries()
            _state["target"] = nil
            TargetClassifyAndWire()
        end)
        bus("SPELLS_CHANGED", "MSUF_RANGEFADE", function()
            RebuildPrimaries()
            -- Re-register with potentially new primary spell
            if _targetIsEnemy and _targetRegisteredSpell then
                local spell = _pEnemy
                if UnitIsDeadOrGhost and UnitExists("target") and UnitIsDeadOrGhost("target") then spell = _pRes end
                if spell and spell ~= _targetRegisteredSpell then
                    TargetRegisterSpell(spell)
                end
            end
        end)
        bus("PLAYER_TALENT_UPDATE", "MSUF_RANGEFADE", RebuildPrimaries)
        bus("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "MSUF_RANGEFADE", RebuildPrimaries)
        bus("TRAIT_CONFIG_UPDATED", "MSUF_RANGEFADE", RebuildPrimaries)
    end

    local function UnwireTargetEvents()
        if not _targetWired then return end; _targetWired = false
        local unreg = _G.MSUF_EventBus_Unregister
        if type(unreg) ~= "function" then return end
        unreg("SPELL_RANGE_CHECK_UPDATE", "MSUF_RANGEFADE")
        unreg("PLAYER_TARGET_CHANGED", "MSUF_RANGEFADE")
        unreg("PLAYER_ENTERING_WORLD", "MSUF_RANGEFADE")
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
                ApplyMul("target", "target", conf, CheckEnemy("target"))
            else
                ApplyMul("target", "target", conf, CheckFriendly("target"))
            end
        end
    end

    function _G.MSUF_RangeFade_Reset()
        _state["target"] = nil
        local mulT = _G.MSUF_RangeFadeMul
        if type(mulT) == "table" then mulT.target = 1 end
        -- Re-apply on next target event
    end

    function _G.MSUF_RangeFade_Shutdown()
        TargetUnregisterSpell()
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
            UnwireTargetEvents()
            ClearMul("target", "target")
        end
    end

    -- Backwards compat
    function _G.MSUF_RangeFade_Rebuild()
        _G.MSUF_RangeFade_RebuildSpells()
    end

    -- ══════════════════════════════════════════════════════════════
    -- FOCUS/BOSS: Ticker + UNIT_IN_RANGE_UPDATE hybrid (v3)
    -- ══════════════════════════════════════════════════════════════
    local _focusIsEnemy = false
    local _focusEvtFrame = nil
    local _ticker, _tickRate = nil, 0
    local _TICK_COMBAT, _TICK_OOC = 0.5, 2.0

    local function OnFocusFriendlyRange(_, event, arg1)
        if arg1 and arg1 ~= "focus" then return end
        local db = _G.MSUF_DB
        local conf = db and db.focus
        if not conf or conf.rangeFadeEnabled ~= true then ClearMul("focus", "focus"); return end
        if _G.MSUF_UnitEditModeActive == true then ClearMul("focus", "focus"); return end
        ApplyMul("focus", "focus", conf, CheckFriendly("focus"))
    end

    local function EnsureFocusEvtFrame()
        if _focusEvtFrame then return end
        _focusEvtFrame = CreateFrame("Frame")
        _focusEvtFrame:SetScript("OnEvent", OnFocusFriendlyRange)
    end

    local function StopTicker()
        if _ticker then _ticker:Cancel(); _ticker = nil end; _tickRate = 0
    end

    local function TickFn()
        local db = _G.MSUF_DB
        local editMode = (_G.MSUF_UnitEditModeActive == true)

        -- Enemy focus (friendly is event-driven)
        if _focusIsEnemy then
            local conf = db and db.focus
            if conf and conf.rangeFadeEnabled == true and not editMode then
                ApplyMul("focus", "focus", conf, CheckEnemy("focus"))
            else
                ClearMul("focus", "focus")
            end
        end

        -- Boss 1-5
        local bossConf = db and db.boss
        local bossOK = (bossConf and bossConf.rangeFadeEnabled == true and not editMode)
        local frames = _G.MSUF_UnitFrames
        for i = 1, 5 do
            local unit = _bossUnits[i]
            if bossOK then
                local f = frames and frames[unit]
                if f and f.IsShown and f:IsShown() and UnitExists(unit) then
                    ApplyMul(unit, "boss", bossConf, CheckEnemy(unit))
                else
                    if _state[unit] ~= nil then
                        _state[unit] = nil
                        local mulT = _G.MSUF_RangeFadeMul
                        if type(mulT) == "table" and mulT[unit] and mulT[unit] ~= 1 then mulT[unit] = 1 end
                    end
                end
            else
                ClearMul(unit, "boss")
            end
        end
    end

    local function EnsureTicker(rate)
        if not C_Timer_NewTicker then return end
        if _ticker and _tickRate == rate then return end
        StopTicker(); _tickRate = rate; _ticker = C_Timer_NewTicker(rate, TickFn)
    end

    local function DesiredRate()
        return (_G.MSUF_InCombat == true) and _TICK_COMBAT or _TICK_OOC
    end

    local function RangeFadeFBWanted()
        local db = _G.MSUF_DB
        if db and db.focus and db.focus.rangeFadeEnabled == true then return true end
        if db and db.boss  and db.boss.rangeFadeEnabled  == true then return true end
        return false
    end

    local function ClassifyFocus()
        if not UnitExists or not UnitExists("focus") then _focusIsEnemy = false; return end
        _focusIsEnemy = (UnitCanAttack and UnitCanAttack("player", "focus")) and true or false
    end

    -- FB event wiring
    local _fbWired = false
    local function WireFBEvents()
        if _fbWired then return end; _fbWired = true
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("PLAYER_REGEN_DISABLED")
        ef:RegisterEvent("PLAYER_REGEN_ENABLED")
        ef:RegisterEvent("SPELLS_CHANGED")
        ef:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        ef:RegisterEvent("PLAYER_TALENT_UPDATE")
        ef:RegisterEvent("TRAIT_CONFIG_UPDATED")
        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
        ef:RegisterEvent("PLAYER_FOCUS_CHANGED")
        ef:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        ef:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
                if _ticker then EnsureTicker(DesiredRate()) end
            elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD"
                or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
                or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
                RebuildPrimaries()
                for k in pairs(_state) do _state[k] = nil end
            elseif event == "PLAYER_FOCUS_CHANGED" then
                _state["focus"] = nil
                ClassifyFocus()
                if UnitExists("focus") and not _focusIsEnemy then
                    EnsureFocusEvtFrame()
                    _focusEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "focus")
                    OnFocusFriendlyRange(nil, event, "focus")
                else
                    if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
                end
            elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
                for i = 1, 5 do _state[_bossUnits[i]] = nil end
            end
        end)
    end

    function _G.MSUF_RangeFadeFB_RebuildSpells()
        if RangeFadeFBWanted() ~= true then return end
        RebuildPrimaries()
    end

    function _G.MSUF_RangeFadeFB_Reset()
        for k in pairs(_state) do _state[k] = nil end
        local mulT = _G.MSUF_RangeFadeMul
        if type(mulT) ~= "table" then return end
        mulT.focus = 1
        for i = 1, 5 do mulT[_bossUnits[i]] = 1 end
    end

    function _G.MSUF_RangeFadeFB_EvaluateActive(force)
        if RangeFadeFBWanted() then
            WireFBEvents()
            if force == true then for k in pairs(_state) do _state[k] = nil end end
            RebuildPrimaries()
            ClassifyFocus()
            if UnitExists and UnitExists("focus") and not _focusIsEnemy then
                EnsureFocusEvtFrame()
                _focusEvtFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", "focus")
                OnFocusFriendlyRange(nil, "INIT", "focus")
            end
            EnsureTicker(DesiredRate())
            return
        end
        if force == true or _ticker then
            TickFn(); StopTicker()
            if _focusEvtFrame then _focusEvtFrame:UnregisterEvent("UNIT_IN_RANGE_UPDATE") end
            ClearMul("focus", "focus")
            for i = 1, 5 do ClearMul(_bossUnits[i], "boss") end
        end
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
