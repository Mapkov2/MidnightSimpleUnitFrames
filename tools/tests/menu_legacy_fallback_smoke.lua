-- Old page fallback values are intentionally independent of runtime normalization.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local oracle = arg[3]
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    world.env.GetSpecialization = function() return 1 end
    world.env.GetSpecializationInfo = function() return 62 end
    world.env.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62 end }
    world.env.IsInInstance = function() return false, "none" end
    world.env.IsInGroup = function() return false end
    world.widgets.Methods.GetCenter = function() return 0, 0 end
    local load = world.LoadFile
    world.LoadFile = function(self, path, addon, namespace)
        if path:match("/State/MSUF_Profiles.lua$") then
            -- Keep real storage/import/switching, isolate native frame application.
            world.core.ProfileRuntime.Apply = function() end
        end
        if oracle then
            local page = path:match("MSUF_Menu2_(%w+)%.lua$")
            local names = { AdvancedGameplay = true, ResourceExtras = true, SwingTimers = true,
                UnitAlpha = true, UnitRangeFade = true }
            if names[page] then path = oracle .. "/before-" .. page .. ".lua" end
        end
        return load(self, path, addon, namespace)
    end
end })
local M, env, core = mw.M, mw.env, mw.core
-- Exercise old page reads on already-normalized partial/imported profiles;
-- runtime apply is covered by the separate profile corpus and input smokes.
core.ProfileRuntime.Apply = function() end
core.MSUF_RequestGameplayApply = function() return true end
local initProfiles, ensureDB = env.MSUF_InitProfiles, env.MSUF_EnsureDB
local initial = core.ProfileFields.CopySnapshot(env.MSUF_DB)
env.MSUF_InitProfiles = function() end
env.MSUF_EnsureDB = function() end
local errors, checks = {}, 0
local function Check(ok, message)
    checks = checks + 1
    if not ok then errors[#errors + 1] = message end
end
local gameplay = {
    combatTimerAnchor = "none", combatFontSize = 24, lockCombatTimer = false, combatTimerClickThrough = false,
    combatOffsetX = 0, combatOffsetY = -200, lockCombatState = false, combatStateFontSize = 24,
    combatStateDuration = 1.5, combatStateOffsetX = 0, combatStateOffsetY = 80,
    playerTotemsIconSize = 24, playerTotemsOffsetX = 0, playerTotemsOffsetY = -6,
    playerTotemsAnchorFrom = "TOPLEFT", playerTotemsAnchorTo = "BOTTOMLEFT", crosshairThickness = 3, crosshairSize = 40,
    enableCombatTimer = false, enableCombatStateText = false, enablePlayerTotems = false,
    enableCombatCrosshair = false, enableCombatCrosshairMeleeRangeColor = false,
    meleeSpellPerClass = false, meleeSpellPerSpec = false, combatStateEnterText = "+Combat", combatStateLeaveText = "-Combat",
}
local units = { hpBarAlpha = 1, hpBgAlpha = 0.85, powerBarAlpha = 1, powerBarBgAlpha = 0.85,
    alphaExcludeTextPortrait = false, alphaExcludePredictionBars = false, oocFadeEnabled = false, oocFadeAlpha = 0.5,
    rangeFadeEnabled = true, rangeFadeAlpha = 0.4, rangeFadeUpdateRate = 0, rangeFadeLayerMode = "frame" }
local bars = { showIgnorePain = false, ignorePainTimeMarker = true, showArcaneWindow = false,
    arcaneWindowText = "seconds", arcaneWindowTextFrom = 0, arcaneWindowWarnSeconds = 3, arcaneWindowWarnLastGCD = false,
    manaRegenPause = false, manaGainPulse = false, manaUpcomingCost = false,
    resourceExtraWidth = 220, resourceExtraHeight = 8, resourceExtraOffsetX = 0, resourceExtraOffsetY = -18 }
local cases = { { "missing" }, { "bad", "bad" }, { "table", {} }, { "false", false },
    { "true", true }, { "zero", 0 }, { "number", 7 }, { "string", "7" }, { "empty", "" } }
local function Expand(page)
    for _, section in pairs(M.cache[page].sections) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
end
local function Probe(page, scope, defaults)
    -- Rev17 partial imports are not seeded by these pages. Cold build and warm profile switches use the same getters.
    local profile = core.ProfileFields.CopySnapshot(env.MSUF_DB)
    profile.__msufDefaultsRev = 17
    for key in pairs(defaults) do profile[scope][key] = nil end
    env.MSUF_DB = profile
    mw:Select(page)
    if page == "classpower" then M.ClassPowerWorkspace.current:Select("extras") end
    Expand(page)
    local bound = 0
    for key, fallback in pairs(defaults) do
        local _, widget = M.RuntimeControlCatalog.FindBySettingKey(scope .. "." .. key, page)
        if widget then
            bound = bound + 1
            local action = assert(widget._msuf2CommandAction, key .. " lacks real getter")
            for _, case in ipairs(cases) do
                local value = case[2]
                env.MSUF_DB[scope][key] = value
                local expected = value
                if key == "rangeFadeLayerMode" then expected = value == "health" and "health" or "frame"
                elseif action.kind == "slider" then expected = tonumber(value) or fallback
                elseif action.kind == "toggle" then
                    if key == "showIgnorePain" or key == "showArcaneWindow" then expected = value == true
                    else expected = (value == nil and fallback or value) and true or false end
                elseif key == "combatStateEnterText" or key == "combatStateLeaveText" then expected = value or fallback
                elseif value == nil then expected = fallback end
                local actual = action.get()
                Check(actual == expected, scope .. "." .. key .. "/" .. case[1] .. ": " .. tostring(actual)
                    .. " (" .. type(actual) .. ") expected " .. tostring(expected) .. " (" .. type(expected) .. ")")
                Check(env.MSUF_DB[scope][key] == value, "getter wrote " .. key)
            end
            env.MSUF_DB[scope][key] = nil
            local other = core.ProfileFields.CopySnapshot(profile)
            other[scope][key] = fallback
            env.MSUF_DB = other
            M.Refresh(M.cache[page].ctx)
            Check(action.get() == fallback, "profile switch/default " .. key)
            env.MSUF_DB = profile
            Check(action.get() == fallback, "profile switch/missing " .. key)
            if action.kind == "dropdown" then
                action.set(false)
                Check(env.MSUF_DB[scope][key] == fallback, "legacy false dropdown setter " .. key)
                env.MSUF_DB[scope][key] = nil
            end
        end
    end
    Check(bound > 0, "no bound controls on " .. page)
end
Probe("gameplay", "gameplay", gameplay)
Probe("classpower", "bars", bars)
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    if M.pages["uf_" .. unit] then Probe("uf_" .. unit, unit, units) end
end
local markDefaults = { target = "PLAYER", resource = "ALL", mode = "PERCENT", direction = "ABOVE",
    value = 50, width = 2, mark = true, threshold = false }
env.MSUF_DB.bars.resourceMarks = { { mode = "PERCENT", target = "PLAYER", resource = "ALL" } }
for key, fallback in pairs(markDefaults) do
    local record = assert(M.RuntimeControlCatalog.Get("menu2.classpower.advanced.resource.extras.marks." .. key))
    local action = assert(record.widget._msuf2CommandAction)
    for _, case in ipairs(cases) do
        local value = case[2]
        env.MSUF_DB.bars.resourceMarks[1][key] = value
        local expected = value or fallback
        if action.kind == "slider" then expected = tonumber(value) or fallback
        elseif action.kind == "toggle" then expected = value ~= false and (key == "mark" or value == true) end
        Check(action.get() == expected, "selected rule " .. key .. "/" .. case[1])
        Check(env.MSUF_DB.bars.resourceMarks[1][key] == value, "selected-rule getter wrote " .. key)
    end
    env.MSUF_DB.bars.resourceMarks[1][key] = fallback
end
if M.pages.swingtimers then
    mw:Select("swingtimers")
    Expand("swingtimers")
    local count = 0
    for _, attack in ipairs(core.SwingTimer.CueAttacks()) do
        local _, widget = M.RuntimeControlCatalog.FindBySettingKey("swingTimers.main." .. attack.key, "swingtimers")
        local action = assert(widget and widget._msuf2CommandAction, "attack text binding missing")
        count = count + 1
        for _, case in ipairs(cases) do
            env.MSUF_DB.swingTimers.main[attack.key] = case[2]
            local inherited = core.SwingTimer.Get("main", attack.key)
            Check(action.get() == (inherited or ""), "attack adapter " .. attack.key .. "/" .. case[1])
        end
        env.MSUF_DB.swingTimers.main[attack.key] = "Override"
        Check(action.get() == "Override", "attack override lost")
        env.MSUF_DB.swingTimers.main[attack.key] = ""
        Check(action.get() == "", "empty attack inheritance lost")
    end
    Check(count == 4, "all four attack labels required")
end
-- The real staged importer and profile switch keep the same cached UI getters.
-- Only the unavailable binary codec and native rendering are fixture seams.
env.MSUF_DB = initial
env.MSUF_InitProfiles, env.MSUF_EnsureDB = initProfiles, ensureDB
initProfiles()
local active = env.MSUF_ActiveProfile
local captured
env.MSUF_EncodeCompactTableMSUF3 = function(value)
    captured = core.ProfileFields.CopySnapshot(value)
    return "MSUF3:captured"
end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
Check(type(env.MSUF_ExportSelectionToString("all")) == "string", "real export failed")
local payload = captured.msuf6 and captured.msuf6.payload or captured.payload
payload.__msufDefaultsRev = 17
payload.gameplay = { enableCombatTimer = false, playerTotemsIconSize = "bad", playerTotemsOffsetY = 0 }
env.MSUF_TryDecodeCompactString = function() return core.ProfileFields.CopySnapshot(captured) end
local imported, why = env.MSUF_ImportIntoNewProfile("Legacy UI", "MSUF3:captured")
Check(imported == true, "real import refused: " .. tostring(why))
if imported then
    for key, fallback in pairs(gameplay) do
        local _, widget = M.RuntimeControlCatalog.FindBySettingKey("gameplay." .. key, "gameplay")
        local action = widget and widget._msuf2CommandAction
        if action then
            local value = env.MSUF_DB.gameplay[key]
            local expected = value
            if action.kind == "slider" then expected = tonumber(value) or fallback
            elseif action.kind == "toggle" then expected = (value == nil and fallback or value) and true or false
            elseif key == "combatStateEnterText" or key == "combatStateLeaveText" then expected = value or fallback
            elseif value == nil then expected = fallback end
            Check(action.get() == expected, "actual imported getter drift: " .. key)
        end
    end
    Check(env.MSUF_SwitchProfile(active) == true, "actual switch back failed")
    Check(env.MSUF_SwitchProfile("Legacy UI") == true, "actual imported profile switch failed")
    local _, icon = M.RuntimeControlCatalog.FindBySettingKey("gameplay.playerTotemsIconSize", "gameplay")
    Check(icon._msuf2CommandAction.get() == (tonumber(env.MSUF_DB.gameplay.playerTotemsIconSize) or 24),
        "cached getter did not follow actual imported profile switch")
end
assert(#errors == 0, flavor .. " legacy fallback failures:\n" .. table.concat(errors, "\n"))
print("menu_legacy_fallback_smoke " .. flavor .. ": " .. checks .. " real getter/type/profile-switch checks OK")
