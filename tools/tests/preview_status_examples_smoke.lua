-- Status examples use private scene configuration and never enable live PvP artwork.
local root, flavor = assert(arg[1]):gsub('\\','/'), arg[2] or 'Mainline'
local MenuWorld = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local flagged, warMode = false, false
local targetFlagged, focusFlagged, targetFFA, targetIsPlayer = false, false, false, true
local eliteUnits = {
    target = { classification = "normal", level = 30, player = false },
    focus = { classification = "normal", level = 30, player = false },
}
local eliteClassReads, eliteLevelReads = 0, 0
local instanceType, instanceReads, pvpBadgesDisabled = "none", 0, false
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local secretFlag = Secrets.New("boolean")
local helpfulAuras, consumptionReads = {}, 0
local EMPTY_AURAS = {}
local playerFFA, pvpTimerRunning, pvpTimerMs, pvpTimerValueReads = false, false, 0, 0
local mw = MenuWorld.Open(root, flavor, { page = 'uf_target', clientScriptBindings = true,
    tocMetadata = true, beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        world.env.C_Secrets = setmetatable({
            ShouldAurasBeSecret = function() return false end,
        }, { __index = world.env.C_Secrets })
        world.env.C_UnitAuras = setmetatable({
            GetUnitAuras = function(unit, filter)
                local source = debug.getinfo(2, "S").source
                if source:find("MSUF_UF_Status_Indicators.lua", 1, true) then
                    assert(filter == "HELPFUL", "unexpected consumption aura filter")
                    consumptionReads = consumptionReads + 1
                    return helpfulAuras[unit] or EMPTY_AURAS
                end
                return EMPTY_AURAS
            end,
        }, { __index = world.env.C_UnitAuras })
        local unitExists = world.env.UnitExists
        world.env.UnitExists = function(unit)
            return unit == "player" or unit == "target" or unit == "focus" or unitExists(unit)
        end
        world.env.UnitIsPlayer = function(unit)
            local eliteUnit = eliteUnits[unit]
            if eliteUnit and eliteUnit.active then return eliteUnit.player end
            if unit == "target" then return targetIsPlayer end
            return unit == "player" or unit == "focus"
        end
        local unitLevel = world.env.UnitLevel
        world.env.UnitLevel = function(unit)
            local eliteUnit = eliteUnits[unit]
            if eliteUnit and eliteUnit.active then
                if debug.getinfo(2, "S").source:find("MSUF_UF_Status_Indicators.lua", 1, true) then
                    eliteLevelReads = eliteLevelReads + 1
                end
                return eliteUnit.level
            end
            if unitLevel then return unitLevel(unit) end
            return 30
        end
        world.env.UnitClassification = function(unit)
            local eliteUnit = eliteUnits[unit]
            if eliteUnit and eliteUnit.active then
                if debug.getinfo(2, "S").source:find("MSUF_UF_Status_Indicators.lua", 1, true) then
                    eliteClassReads = eliteClassReads + 1
                end
                return eliteUnit.classification
            end
            return "normal"
        end
        world.env.UnitIsConnected = world.env.UnitExists
        world.env.UnitIsDeadOrGhost = function() return false end
        world.env.UnitIsDead = function() return false end
        world.env.UnitIsGhost = function() return false end
        world.env.UnitIsAFK = function() return false end
        world.env.UnitIsDND = function() return false end
        world.env.UnitIsPVP = function(unit)
            if unit == "target" then return targetFlagged end
            if unit == "focus" then return focusFlagged end
            return unit == "player" and flagged
        end
        world.env.UnitIsPVPFreeForAll = function(unit)
            return (unit == "target" and targetFFA) or (unit == "player" and playerFFA)
        end
        -- The native PvP flag timer: whether it runs, and its remaining milliseconds.
        world.env.IsPVPTimerRunning = function() return pvpTimerRunning end
        world.env.GetPVPTimer = function()
            pvpTimerValueReads = pvpTimerValueReads + 1
            return pvpTimerMs
        end
        world.env.UnitFactionGroup = function(unit) return unit == "target" and "Horde" or "Alliance" end
        world.env.IsInInstance = function()
            instanceReads = instanceReads + 1
            return instanceType ~= "none", instanceType
        end
        world.env.Enum.GameRule = { UnitFramePvPContextualDisabled = 1 }
        world.env.C_GameRules = { IsGameRuleActive = function() return pvpBadgesDisabled end }
        local nativeIsSecret = world.env.issecretvalue
        world.env.issecretvalue = function(value)
            return Secrets.IsSecret(value) or (nativeIsSecret and nativeIsSecret(value)) or false
        end
        world.env.C_PvP = {
            IsWarModeDesired = function() return warMode end,
            IsWarModeActive = function() return warMode end,
        }
    end })
local M, U, UF, GF = mw.M, mw.core.UFPreview, mw.core.UF, mw.core.GF
local failures, checks = {}, 0
local function check(value, why)
    checks = checks + 1
    if not value then failures[#failures + 1] = why; print('FAIL ' .. why) end
end
local function settle() mw:RunTimers(20000); M.Theme.StopAllMenuAnimations() end
local function shown(r) return r and r:IsShown() == true and (not r.GetAlpha or r:GetAlpha() > 0) end
local function gated(pvp) return pvp and (pvp.enabled == false or pvp.contextGated == true) end
local targetDriven = flavor == "Mainline" or flavor == "Forever"
local function CheckTargetSpec(pvp)
    if targetDriven then
        check(pvp.enabled and pvp.followsTarget and not pvp.contextGated,
            "the live target must follow its own flag outside the player PvP context")
    else
        check(gated(pvp), "Classic target PvP must still follow the client context")
    end
end
settle()
check(not UF.PVPIndicatorContextActive(), 'fixture must be outside PvP context')
local cfg = M.EnsureDB().target
for _, key in ipairs({ 'showLeaderIcon', 'showEliteIcon', 'showRaidGroupInName', 'showPvpIndicator' }) do cfg[key] = true end
local live = assert(UF.Config.CompileSpec('target'))
local beforeEnabled, beforeGate = live.status.pvp.enabled, live.status.pvp.contextGated
CheckTargetSpec(live.status.pvp)
U.SetStatusPreviewMode('all'); U.active:RequestRefresh('SETTINGS'); settle()
local box, frame = U.active, U.active.mock._body
local fields = { 'leaderIcon', 'assistIcon', 'eliteIcon', 'raidGroupNameText', 'pvpIndicatorIcon' }
for _, field in ipairs(fields) do check(shown(frame[field]), 'all target examples includes ' .. field) end
box._animationEnabled = true; box:RequestRefresh('SETTINGS'); settle()
for _, time in ipairs({ 0.3, 1.7, 4.2 }) do
    box._animationElapsed = time
    check(U.RefreshAnimation(box) ~= false, 'unit animation accepted')
    for _, field in ipairs(fields) do check(shown(frame[field]), 'all target animated example includes ' .. field) end
end
box._animationEnabled = nil
check(live.status.pvp.enabled == beforeEnabled and live.status.pvp.contextGated == beforeGate,
    'unit preview did not mutate the independent live spec')
local liveAfter = UF.Config.CompileSpec('target')
CheckTargetSpec(liveAfter.status.pvp)
check(frame.MSUFSpec.status ~= live.status and frame.MSUFSpec.status.pvp ~= live.status.pvp,
    'unit preview owns independent status and PvP tables')
cfg.showPvpIndicator = false; box:RequestRefresh('SETTINGS'); settle()
check(not shown(frame.pvpIndicatorIcon), 'unit disabled PvP stays hidden in all')
check(frame.MSUFSpec.status.pvp.enabled == false, 'unit private PvP flag respects disabled setting')
if targetDriven then
    local db = M.EnsureDB()
    local savedTarget, savedFocus = UF.frames.target, UF.frames.focus
    local function Spawn(unit)
        local unitFrame = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
        unitFrame.MSUFUnitKey = unit
        UF.frames[unit] = unitFrame
        db[unit].showPvpIndicator = true
        UF.Config.RefreshUnit(unit)
        UF.ApplySpec(unitFrame, UF.Config.GetSpec(unit), nil, { StatusIndicators = true, PVPIndicator = true, EliteIndicator = true })
        return unitFrame
    end
    local target, focus = Spawn("target"), Spawn("focus")
    local targetIcon, focusIcon = target.pvpIndicatorIcon, focus.pvpIndicatorIcon
    check(not shown(targetIcon) and not shown(focusIcon), "the faction option must default off for unflagged players")

    if flavor == "Forever" then
        local renderer = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Indicators.lua"
        local stopWatch = Secrets.Watch(renderer, { strict = true })
        for _, unit in ipairs({ "target", "focus" }) do
            local unitFrame = UF.frames[unit]
            local icon = assert(unitFrame.eliteIcon)
            local data = eliteUnits[unit]
            local changeEvent = unit == "target" and "PLAYER_TARGET_CHANGED" or "PLAYER_FOCUS_CHANGED"
            data.active = true
            for _, classification in ipairs({ "elite", "rareelite", "rare", "worldboss" }) do
                data.classification = classification
                mw.world:FireEvent("UNIT_CLASSIFICATION_CHANGED", unit)
                check(shown(icon), unit .. " must show " .. classification)
            end
            data.classification, data.level = "normal", -1
            local beforeLevels, beforeClasses = eliteLevelReads, eliteClassReads
            for _ = 1, 4 do mw.world:FireEvent("UNIT_CLASSIFICATION_CHANGED", unit) end
            check(not shown(icon), unit .. " normal skull-level NPC must clear the elite icon")
            check(eliteClassReads - beforeClasses == 4 and eliteLevelReads == beforeLevels,
                unit .. " elite refresh must read classification once and skip level reads")

            data.classification = "elite"
            mw.world:FireEvent(changeEvent)
            check(shown(icon), unit .. " must repaint an elite NPC on identity change")
            data.player = Secrets.New("boolean")
            beforeClasses = eliteClassReads
            mw.world:FireEvent(changeEvent)
            check(not shown(icon) and eliteClassReads == beforeClasses, unit .. " unknown identity must clear the elite icon")
            data.player = true
            mw.world:FireEvent(changeEvent)
            check(not shown(icon), unit .. " player must never inherit an elite icon")
            data.player, data.classification = false, Secrets.New("string")
            mw.world:FireEvent("UNIT_CLASSIFICATION_CHANGED", unit)
            check(not shown(icon), unit .. " restricted classification must keep the elite icon hidden")
            data.classification = "elite"
            mw.world:FireEvent(changeEvent)
            check(shown(icon), unit .. " must show a newly selected elite NPC")
            data.active = false
            mw.world:FireEvent(changeEvent)
        end
        local violations = stopWatch()
        check(#violations == 0, "elite indicator secret violations: " .. table.concat(violations, "\n"))
    end

    local baselineReads = instanceReads
    targetFlagged, focusFlagged = true, true
    mw.world:FireEvent("UNIT_FACTION", "target")
    mw.world:FireEvent("UNIT_FACTION", "focus")
    check(shown(targetIcon) and shown(focusIcon), "flagged targets and focus must show while the player is unflagged")
    check(instanceReads == baselineReads, "unit flag updates must use the cached world and game-rule scope")
    targetFlagged, focusFlagged = false, false
    mw.world:FireEvent("UNIT_FACTION", "target")
    mw.world:FireEvent("UNIT_FACTION", "focus")

    M.unitStatusSelection = M.unitStatusSelection or {}
    M.unitStatusSelection.target = "statusPvp"
    assert(mw:Select("uf_target") ~= false)
    for _, body in pairs(M.cache.uf_target.sections) do
        local entry = body._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    settle()
    local toggle
    for _, widget in ipairs(mw.world.widgets.frames) do
        local contract = widget._msuf2ExactTargetContracts
        if contract and contract.unitStatus and contract.unitStatus.statusPvp == "target.pvpIndicatorShowOpenWorldFaction" then
            toggle = widget
            break
        end
    end
    assert(toggle and toggle:IsShown(), "missing open-world faction switch on the selected PvP indicator")
    toggle:Click("LeftButton")
    check(cfg.pvpIndicatorShowOpenWorldFaction and shown(targetIcon), "the menu switch must paint the unflagged target immediately")
    check(not shown(focusIcon), "the faction option is stored per unit")

    targetIsPlayer = false
    mw.world:FireEvent("PLAYER_TARGET_CHANGED")
    check(not shown(targetIcon), "an unflagged NPC must not show a faction badge")
    targetIsPlayer = true
    mw.world:FireEvent("PLAYER_TARGET_CHANGED")
    check(shown(targetIcon), "a new player target must seed the faction badge")
    targetFlagged = secretFlag
    local rendererPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Indicators.lua"
    local stopWatch = Secrets.Watch(rendererPath, { strict = true })
    mw.world:FireEvent("UNIT_FACTION", "target")
    local violations = stopWatch()
    check(#violations == 0, "PvP rendering must guard restricted flags: " .. table.concat(violations, ", "))
    check(not shown(targetIcon), "a restricted PvP state must not be treated as unflagged")
    targetFlagged = false

    instanceType = "party"
    mw.world:FireEvent("ZONE_CHANGED_NEW_AREA")
    check(not shown(targetIcon), "unflagged faction badges are hidden inside instances")
    targetFlagged = true
    mw.world:FireEvent("UNIT_FACTION", "target")
    check(shown(targetIcon), "actual target PvP flags still display in instances")
    pvpBadgesDisabled = true
    mw.world:FireEvent("ACTIVE_GAME_MODE_UPDATED", 1)
    check(not shown(targetIcon), "Blizzard's PvP game rule must hide the target badge")
    targetFlagged, targetFFA, pvpBadgesDisabled, instanceType = false, true, false, "none"
    mw.world:FireEvent("PLAYER_ENTERING_WORLD", false, false)
    check(shown(targetIcon), "free-for-all must still display through the native path")
    targetFFA = false
    toggle:Click("LeftButton")
    check(not cfg.pvpIndicatorShowOpenWorldFaction and not shown(targetIcon), "turning the faction switch off must hide the badge")

    cfg.pvpIndicatorShowOpenWorldFaction = true
    local copied = M.UnitPage.CopyUnitSettings("target", "focus", { status = true })
    check(copied == true and db.focus.pvpIndicatorShowOpenWorldFaction == true, "status copy must transfer the faction option to focus")
    local resetId = M.UnitPage.ControlMeta({ key = "uf_target" }, "status.selected.reset", "action").controlId
    local reset = assert(M.RuntimeControlCatalog.Get(resetId), "missing status reset action")
    reset.widget:Click("LeftButton")
    check(cfg.pvpIndicatorShowOpenWorldFaction == nil, "resetting the selected PvP icon must clear the faction option")
    cfg.pvpIndicatorShowOpenWorldFaction = true
    cfg.showPvpIndicator = false
    mw.core.Require("MSUF_RequestStatusPvpIndicatorRefresh", "preview_status_examples_smoke")("target")
    check(not shown(targetIcon), "the indicator master switch must also hide faction badges")
    cfg.pvpIndicatorShowOpenWorldFaction = nil
    db.focus.pvpIndicatorShowOpenWorldFaction = nil
    UF.frames.target, UF.frames.focus = savedTarget, savedFocus
end
assert(mw:Select('gf_layout') ~= false); settle(); M.gfScope = 'party'; GF.EnsureDB()
local conf = GF.GetConf('party')
conf.enabled, conf.pvpIcon = true, true
GF.InvalidateCompiledSpecs('party')
local base = GF.CompileSpec('party')
local basePvP, baseEnabled, baseGate = base.status.pvp, base.status.pvp.enabled, base.status.pvp.contextGated
check(gated(basePvP), 'configured live group PvP remains gated outside context')
M.SetMenuStateValue('gfStatusPreviewMode', 'all')
local group = M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = 'gf_layout' })
group:Show(); group._stage:SetSize(600, 220); group:Refresh('SETTINGS'); settle()
local cell = group._msufGFRenderState.mock._cell
check(shown(cell.pvpIndicatorIcon), 'all group examples includes out-of-context PvP')
check(cell.MSUFSpec.status ~= base.status and cell.MSUFSpec.status.pvp ~= basePvP,
    'group preview owns independent status and PvP overlays')
group._animationEnabled = true; group:Refresh('SETTINGS'); settle()
for _, time in ipairs({ 0.3, 1.7, 4.2 }) do
    group._animationElapsed = time
    check(group:RefreshAnimation() ~= false, 'group animation accepted')
    check(shown(cell.pvpIndicatorIcon), 'all group animated example includes out-of-context PvP')
end
group._animationEnabled = nil
check(base.status.pvp == basePvP and basePvP.enabled == baseEnabled and basePvP.contextGated == baseGate,
    'group preview did not mutate the shared live status/PvP spec')
check(gated(GF.CompileSpec('party').status.pvp), 'live group recompile stays context-gated after preview')
conf.pvpIcon = false; GF.InvalidateCompiledSpecs('party'); group:Refresh('SETTINGS'); settle()
check(not shown(cell.pvpIndicatorIcon), 'group disabled PvP stays hidden in all')
check(cell.MSUFSpec.status.pvp.enabled == false, 'group private PvP flag respects disabled setting')
-- WoW Forever: the player's PvP flag countdown beside the icon follows the
-- native timer through its unitless event, the flag events and spec applies.
local function CheckForeverPVPCountdown(player, icon, toggle, db, prior)
    local widgets = mw.world.widgets
    local fs = player.pvpIndicatorTimerText
    check(fs ~= nil, "the Forever player frame must own the PvP countdown text")
    if not fs then return end
    -- The world's own player frame no longer receives this smoke's settings
    -- refreshes; keep it hidden so only the frames under test count.
    if prior then prior:Hide() end
    local element = UF.elements.PVPIndicator
    local function Has(list, name)
        for _, event in ipairs(list or {}) do
            if event == name then return true end
        end
        return false
    end
    check(Has(element.GetUnitlessEvents(player, player.MSUFSpec), "PVP_TIMER_UPDATE")
        and not Has(element.GetEvents(player, player.MSUFSpec), "PVP_TIMER_UPDATE"),
        "the player-wide timer event must use the player frame's unitless route")
    local firstTicker = #widgets.tickers + 1
    local function Active()
        local found, count = nil, 0
        for i = firstTicker, #widgets.tickers do
            local ticker = widgets.tickers[i]
            if not ticker.cancelled and ticker.delay == 1 then found, count = ticker, count + 1 end
        end
        return found, count
    end
    local function Tick(seconds)
        widgets:AdvanceTime(seconds)
        local ticker = Active()
        if ticker then ticker.callback() end
    end
    local function Expect(text, tickers, why)
        local actual = shown(fs) and fs:GetText() or nil
        local _, count = Active()
        check(actual == text, why .. " (text " .. tostring(actual) .. ")")
        check(count == tickers, why .. " (" .. count .. " active tickers)")
    end
    local function Fire(event, ...) mw.world:FireEvent(event, ...) end

    pvpTimerRunning, pvpTimerMs = false, 0
    Fire("PVP_TIMER_UPDATE")
    check(shown(icon), "a flag without a running timer keeps the icon")
    Expect(nil, 0, "no countdown while the native timer is stopped")

    pvpTimerRunning, pvpTimerMs = true, 300000
    Fire("PVP_TIMER_UPDATE", "player")
    Expect("5:00", 1, "the native timer event must start the countdown with its documented unit")
    local countdownToggle
    for _, widget in ipairs(widgets.frames) do
        local contract = widget._msuf2ExactTargetContracts
        if contract and contract.unitStatus and contract.unitStatus.statusPvp == "player.pvpIndicatorCountdownEnabled" then
            countdownToggle = widget
            break
        end
    end
    check(shown(countdownToggle), "the Forever PvP menu must offer a separate countdown switch")
    if countdownToggle then
        countdownToggle:Click("LeftButton")
        check(db.player.pvpIndicatorCountdownEnabled == false and shown(icon), "turning off the timer keeps the live PvP flag")
        Expect(nil, 0, "turning off the timer stops the live ticker")
        countdownToggle:Click("LeftButton")
        Expect("5:00", 1, "turning the timer back on reads the native remaining time")
    end
    local _, relativeTo = fs:GetPoint(1)
    check(relativeTo == icon, "the countdown must sit beside the PvP icon")
    Tick(1)
    Expect("4:59", 1, "the countdown repaints once per second")
    Tick(61)
    Expect("3:58", 1, "the countdown follows the native remaining time")
    pvpTimerMs = 300000
    Fire("PVP_TIMER_UPDATE")
    Expect("5:00", 1, "a native timer reset restarts the countdown on the same ticker")
    Tick(299.5)
    Expect("0:01", 1, "the final second still counts")
    Tick(0.5)
    Expect(nil, 0, "expiry must hide the countdown and stop the ticker")
    check(shown(icon), "the icon stays while the client still reports the flag after expiry")
    Tick(1)
    Expect(nil, 0, "no work remains after expiry")

    pvpTimerRunning, pvpTimerMs = true, 120000
    Fire("PVP_TIMER_UPDATE")
    Expect("2:00", 1, "a new native timer shows again")
    pvpTimerRunning = false
    Fire("PVP_TIMER_UPDATE")
    Expect(nil, 0, "a stopped native timer hides the countdown")
    check(shown(icon), "the icon stays while flagged with the timer stopped")
    pvpTimerRunning, pvpTimerMs = true, 0
    Fire("PVP_TIMER_UPDATE")
    Expect(nil, 0, "a running timer at zero shows no countdown")

    pvpTimerRunning, pvpTimerMs = true, 90000
    Fire("PVP_TIMER_UPDATE")
    Expect("1:30", 1, "countdown before the flag clears")
    flagged = false
    Fire("PLAYER_PVP_FLAG_CHANGED", false)
    check(not shown(icon), "clearing the flag hides the icon")
    Expect(nil, 0, "clearing the flag removes the countdown and its ticker")

    -- An enemy guard flags the player in combat; the client may report the
    -- timer before or after the flag.
    widgets:SetCombat(true)
    pvpTimerRunning, pvpTimerMs = false, 0
    flagged = true
    Fire("UNIT_FACTION", "player")
    check(shown(icon), "a PvE guard flag must show the icon at once in combat")
    Expect(nil, 0, "no countdown before the client starts the timer")
    pvpTimerRunning, pvpTimerMs = true, 300000
    Fire("PVP_TIMER_UPDATE")
    Expect("5:00", 1, "the native timer starts the countdown in combat")
    Tick(10)
    Expect("4:50", 1, "the countdown ticks in combat")
    flagged = false
    Fire("PLAYER_PVP_FLAG_CHANGED", false)
    Expect(nil, 0, "the cleared flag ends the countdown in combat")
    pvpTimerMs = 240000
    Fire("PVP_TIMER_UPDATE")
    check(not shown(icon), "a timer event before the flag shows no icon")
    Expect(nil, 0, "a timer event before the flag shows no countdown")
    flagged = true
    Fire("UNIT_FACTION", "player")
    Expect("4:00", 1, "the later flag shows icon and countdown together")
    Fire("PLAYER_PVP_FLAG_CHANGED", true)
    Expect("4:00", 1, "repeated flag inputs keep one ticker")
    widgets:SetCombat(false)

    playerFFA = true
    Fire("UNIT_FACTION", "player")
    check(shown(icon), "free-for-all keeps its icon")
    Expect(nil, 0, "Blizzard suppresses the countdown in free-for-all")
    playerFFA = false
    Fire("UNIT_FACTION", "player")
    Expect("4:00", 1, "leaving free-for-all restores the countdown")
    pvpBadgesDisabled = true
    Fire("ACTIVE_GAME_MODE_UPDATED", 1)
    Fire("PVP_TIMER_UPDATE")
    check(not shown(icon), "the PvP game rule hides the icon")
    Expect(nil, 0, "the PvP game rule hides the countdown")
    pvpBadgesDisabled = false
    Fire("ACTIVE_GAME_MODE_UPDATED", 1)
    Fire("PVP_TIMER_UPDATE")
    Expect("4:00", 1, "the restored game mode shows the countdown")

    toggle:Click("LeftButton")
    check(db.player.showPvpIndicator == false and not shown(icon), "disabling hides the icon")
    Expect(nil, 0, "disabling the indicator stops the countdown at once")
    toggle:Click("LeftButton")
    Expect("4:00", 1, "re-enabling while the timer runs shows the countdown")

    player:Hide()
    Tick(1)
    Expect(nil, 0, "a hidden player frame stops the countdown work")
    player:Show()
    Fire("PVP_TIMER_UPDATE")
    Expect("4:00", 1, "the shown frame resumes from the native timer")

    local reloaded = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
    reloaded.MSUFUnitKey = "player"
    pvpTimerMs = 200000
    UF.ApplySpec(reloaded, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })
    local reloadedText = reloaded.pvpIndicatorTimerText
    check(shown(reloaded.pvpIndicatorIcon) and reloadedText and shown(reloadedText) and reloadedText:GetText() == "3:20",
        "a frame applied after reload reads the running native timer")
    local _, count = Active()
    check(count == 1, "two player frames share one countdown ticker")
    UF.elements.PVPIndicator.Disable(reloaded)
    check(not shown(reloadedText), "the disabled element hides its countdown")
    reloaded:Hide()

    local renderer = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Indicators.lua"
    local stopWatch = Secrets.Watch(renderer, { strict = true })
    pvpTimerRunning = Secrets.New("boolean")
    Fire("PVP_TIMER_UPDATE")
    Expect(nil, 0, "a restricted timer state shows no countdown")
    pvpTimerRunning, pvpTimerMs = true, Secrets.New("number")
    Fire("PVP_TIMER_UPDATE")
    Expect(nil, 0, "a restricted remaining time shows no countdown")
    local violations = stopWatch()
    check(#violations == 0, "PvP countdown used restricted timer data: " .. table.concat(violations, ", "))
    check(shown(icon), "restricted timer data keeps the actual flag icon")
    pvpTimerRunning, pvpTimerMs = false, 0
    Fire("PVP_TIMER_UPDATE")
    flagged = false
    Fire("PLAYER_PVP_FLAG_CHANGED", false)
    local box = U.active
    local function preview(mode, selection)
        U.SelectStatusIcon(selection)
        U.SetStatusPreviewMode(mode)
        box:RequestRefresh("SETTINGS")
        settle()
        return box.mock._body
    end
    local beforePreviewReads = pvpTimerValueReads
    local previewFrame = preview("current", "statusPvp")
    local previewText = previewFrame.pvpIndicatorTimerText
    check(shown(previewFrame.pvpIndicatorIcon) and shown(previewText), "current PvP preview paints the flag and its sample time while unflagged")
    previewFrame = preview("all", "statusPvp")
    check(shown(previewFrame.pvpIndicatorIcon) and shown(previewFrame.pvpIndicatorTimerText), "all status symbols includes the PvP countdown")
    box._animationEnabled = true
    box._animationElapsed = 1
    check(U.RefreshAnimation(box) ~= false, "PvP preview animation can render")
    local firstText = previewText and previewText:GetText()
    box._animationElapsed = 3
    U.RefreshAnimation(box)
    check(previewText and shown(previewText) and previewText:GetText() ~= firstText, "preview clock advances the countdown")
    box._animationEnabled = nil
    previewFrame = preview("current", "raidmarker")
    check(not shown(previewFrame.pvpIndicatorTimerText), "previewing another status hides the countdown")
    previewFrame = preview("current", "statusPvp")
    if countdownToggle then
        countdownToggle:Click("LeftButton")
        settle()
        check(shown(previewFrame.pvpIndicatorIcon) and not shown(previewFrame.pvpIndicatorTimerText),
            "disabling the countdown keeps the preview's PvP icon")
        countdownToggle:Click("LeftButton")
        settle()
        check(shown(previewFrame.pvpIndicatorTimerText), "enabling the countdown repaints the preview")
    end
    check(not shown(icon) and pvpTimerValueReads == beforePreviewReads, "preview never reads live timer data or changes the live PvP flag")
    if prior then prior:Show() end
end

-- Apply the option while the player's live flag is already set, then exercise
-- the native unit event on the same frame without a spec refresh.
do
    local db = M.EnsureDB()
    local saved = db.player.showPvpIndicator
    local player = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
    player.MSUFUnitKey = "player"
    local prior = UF.frames.player
    local index = #UF.frameList + 1
    UF.frames.player, UF.frameList[index] = player, player
    db.player.showPvpIndicator = false
    UF.Config.RefreshUnit("player")
    UF.ApplySpec(player, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })

    M.unitStatusSelection = M.unitStatusSelection or {}
    M.unitStatusSelection.player = "statusPvp"
    assert(mw:Select("uf_player") ~= false)
    for _, body in pairs(M.cache.uf_player.sections) do
        local entry = body._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    settle()
    local toggle
    for _, widget in ipairs(mw.world.widgets.frames) do
        local contract = widget._msuf2ExactTargetContracts
        if contract and contract.unitStatus and contract.unitStatus.statusPvp == "player.showPvpIndicator" then
            toggle = widget
            break
        end
    end
    assert(toggle, "missing player PvP indicator switch")

    flagged = true
    if flavor == "Mainline" then
        warMode = true
        mw.world:FireEvent("WAR_MODE_STATUS_UPDATE", true)
    end
    mw.world:FireEvent("UNIT_FACTION", "player")
    check(not shown(player.pvpIndicatorIcon), "disabled option must hide the PvP icon")
    toggle:Click("LeftButton")
    local icon = player.pvpIndicatorIcon
    check(db.player.showPvpIndicator == true and shown(icon),
        "enabling the option while flagged must show the player PvP icon immediately")
    toggle:Click("LeftButton")
    check(db.player.showPvpIndicator == false and not shown(icon),
        "disabling the option must hide the icon while the player is still flagged")
    toggle:Click("LeftButton")
    check(shown(icon), "re-enabling the option must show the icon while still flagged")

    flagged = false
    -- The refresh also works when dispatch supplies no payload.
    mw.world:FireEvent("PVP_TIMER_UPDATE")
    check(not shown(icon), "the player icon must hide when the native PvP timer event clears the flag")
    mw.world.widgets:SetCombat(true)
    flagged = true
    mw.world:FireEvent("UNIT_FACTION", "player")
    check(icon and icon:IsShown(), "UNIT_FACTION must show the player PvP icon immediately in combat")
    mw.world.widgets:SetCombat(false)
    if flavor == "Forever" then
        flagged = false
        mw.world:FireEvent("PLAYER_PVP_FLAG_CHANGED", false)
        check(not shown(icon), "the native Forever flag event must hide the player icon")
        flagged = true
        mw.world:FireEvent("PLAYER_PVP_FLAG_CHANGED", true)
        check(shown(icon), "the native Forever flag event must show the player icon")
        CheckForeverPVPCountdown(player, icon, toggle, db, prior)
    elseif flavor == "Mainline" then
        check(shown(icon), "War Mode on must show the actual PvP flag")
        mw.world:FireEvent("WAR_MODE_STATUS_UPDATE", false)
        check(not shown(icon), "War Mode off must hide the icon even while WoW still reports PvP")
        warMode = false
        mw.world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        mw.world:FireEvent("UNIT_FACTION", "player")
        mw.world:FireEvent("PVP_TIMER_UPDATE")
        check(not shown(icon), "later flag events must not restore the disabled War Mode icon")

        local reloaded = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
        reloaded.MSUFUnitKey = "player"
        UF.InvalidatePVPIndicatorContext()
        UF.Config.RefreshUnit("player")
        UF.ApplySpec(reloaded, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })
        check(db.player.showPvpIndicator and not shown(reloaded.pvpIndicatorIcon),
            "with the option enabled, a fresh frame after reload must hide residual War Mode PvP")

        warMode, flagged = true, false
        mw.world:FireEvent("WAR_MODE_STATUS_UPDATE", true)
        check(not shown(icon), "War Mode on must wait for an actual PvP flag")
        flagged = true
        mw.world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        check(shown(icon), "the icon must show when Blizzard confirms the flag in an already open context")
        warMode = false
        mw.world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        check(not shown(icon), "the icon must follow a confirmed War Mode disable")
    end
    if flavor ~= "Forever" then
        check(player.pvpIndicatorTimerText == nil and pvpTimerValueReads == 0,
            "only WoW Forever builds and reads the player PvP countdown")
    end
    db.player.showPvpIndicator = saved
    UF.frames.player = prior
    table.remove(UF.frameList, index)
end

-- Apply the same status element and unit-event dispatch as a live unit frame.
do
    local db = M.EnsureDB()
    local element = UF.elements.StatusTextIndicator
    local fullUpdate = { isFullUpdate = true }
    local renderer = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Indicators.lua"
    local stopWatch = Secrets.Watch(renderer, { strict = true })
    for _, unit in ipairs({ "player", "target" }) do
        local liveFrame = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
        liveFrame.MSUFUnitKey = unit
        local prior = UF.frames[unit]
        local conf = db[unit]
        local oldToggle = conf.statusConsumptionTextEnabled
        local oldAnchor, oldOffset = conf.statusTextAnchor, conf.statusTextOffsetX
        conf.statusTextAnchor, conf.statusTextOffsetX = "TOP", 20
        UF.frames[unit] = liveFrame
        local function Apply(enabled)
            db[unit].statusConsumptionTextEnabled = enabled
            UF.Config.RefreshUnit(unit)
            UF.ApplySpec(liveFrame, UF.Config.GetSpec(unit), nil, { StatusIndicators = true, StatusTextIndicator = true })
        end
        local function CheckRoute(expected)
            local hasAura = false
            for _, event in ipairs(element.GetEvents(liveFrame, liveFrame.MSUFSpec)) do
                if event == "UNIT_AURA" then hasAura = true end
            end
            check(hasAura == expected, unit .. " consumption UNIT_AURA route")
        end
        local function CheckText(expected)
            local text = liveFrame.statusIndicatorText
            check(liveFrame._msufStatusTextValue == expected,
                unit .. " consumption state expected " .. tostring(expected) .. ", got " .. tostring(liveFrame._msufStatusTextValue))
            check(not not shown(text) == (expected ~= nil), unit .. " consumption text visibility")
            if expected then
                check(text and text:GetText() == mw.core.Translate(expected), unit .. " translated " .. expected)
            end
        end
        local function FullUpdate(auras)
            helpfulAuras[unit] = auras
            mw.world:FireEvent("UNIT_AURA", unit, fullUpdate)
        end

        local before = consumptionReads
        helpfulAuras[unit] = { { spellId = 433 } }
        Apply(nil)
        CheckRoute(false)
        mw.world:FireEvent("UNIT_AURA", unit, fullUpdate)
        CheckText(nil)
        check(consumptionReads == before, unit .. " default-off status read helpful auras")

        Apply(true)
        local forever = flavor == "Forever"
        CheckRoute(forever)
        if forever then
            local layout = liveFrame.MSUFSpec.status.statusText.consumption
            check(layout.anchor == "CENTER" and layout.x == 0, unit .. " consumption inherited legacy Dead Text layout")
            CheckText("EATING")
            FullUpdate({ { spellId = 433 }, { spellId = 430 } })
            CheckText("DRINKING")
            before = consumptionReads
            element.Update(liveFrame, "UNIT_HEALTH", unit, 100)
            check(consumptionReads == before, unit .. " health dispatch read helpful auras")
            mw.core.UFStatusRuntime.UpdateStatusText(liveFrame, liveFrame.MSUFSpec.status, "MSUF_AFK_TIMER_TICK")
            check(consumptionReads == before, unit .. " AFK timer tick read helpful auras")
            CheckText("DRINKING")
            FullUpdate({ Secrets.New("table"), { spellId = Secrets.New("number") }, { spellId = 433 } })
            CheckText("EATING")
            FullUpdate({ { spellId = 14823 }, { spellId = 18125 }, { spellId = Secrets.New("number") } })
            CheckText(nil)
            FullUpdate(Secrets.New("table"))
            CheckText(nil)
            before = consumptionReads
            local otherAura = { spellId = 6673, auraInstanceID = 12 }
            helpfulAuras[unit] = { otherAura }
            mw.world:FireEvent("UNIT_AURA", unit, { isFullUpdate = false, addedAuras = { otherAura } })
            CheckText(nil)
            check(consumptionReads == before, unit .. " unrelated aura delta read the aura list")

            local drink = { spellId = 430, auraInstanceID = 13 }
            helpfulAuras[unit] = { otherAura, drink }
            mw.world:FireEvent("UNIT_AURA", unit, { isFullUpdate = false, addedAuras = { drink } })
            CheckText("DRINKING")
            check(consumptionReads == before, unit .. " new drink delta read the aura list")
            helpfulAuras[unit] = { otherAura }
            mw.world:FireEvent("UNIT_AURA", unit, { isFullUpdate = false, removedAuraInstanceIDs = { 13 } })
            CheckText(nil)
            check(consumptionReads == before + 1, unit .. " active aura removal must reconcile once")
            FullUpdate({ { spellId = 430 } })
            CheckText("DRINKING")
            if unit == "target" then
                helpfulAuras.target = EMPTY_AURAS
                mw.world:FireEvent("PLAYER_TARGET_CHANGED")
                CheckText(nil)
                FullUpdate({ { spellId = 430 } })
                CheckText("DRINKING")
            end
            Apply(false)
            CheckRoute(false)
            CheckText(nil)
            before = consumptionReads
            mw.world:FireEvent("UNIT_AURA", unit, fullUpdate)
            check(consumptionReads == before, unit .. " disabled status still read helpful auras")
        else
            CheckText(nil)
            check(consumptionReads == before, unit .. " non-Forever client read consumption auras")
        end
        helpfulAuras[unit] = nil
        conf.statusTextAnchor, conf.statusTextOffsetX = oldAnchor, oldOffset
        Apply(oldToggle)
        UF.frames[unit] = prior
        liveFrame:Hide()
    end
    local violations = stopWatch()
    check(#violations == 0, "consumption renderer used restricted aura data: " .. table.concat(violations, ", "))
end

print(string.format('status examples %s: %d checks, %d failures', flavor, checks, #failures))
assert(#failures == 0, table.concat(failures, '\n'))
