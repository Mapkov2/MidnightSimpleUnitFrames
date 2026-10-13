-- An escaped Menu2 flush error must not poison later castbar snapshots.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local function NewWorld()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
    beforeCore = function(world)
        world.env.MAX_TOTEMS = 4
        world.widgets.Methods.GetNumPoints = function(frame) return #(frame.points or {}) end
    end })
local M, env, core = mw.M, mw.env, mw.core
local castbars = core.Castbars
local Config = castbars and castbars.Config

-- Unrelated native unit-frame/class-resource owners are outside this fixture.
env.MSUF_UFCore_NotifyConfigChanged = function() return false end
env.MSUF_RefreshAllUnitAlphas = function() end
env.MSUF_ClassPower_Apply = function() end
env.MSUF_ApplyModules = function() end
core.MSUF_Gameplay_PlayerTotems_Apply = function() end
local controls = {}
local register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.settingKey and payload.command then
        controls[payload.settingKey] = payload.command
    end
    return register(widget, payload, ...)
end
local function Settle()
    for _ = 1, 3 do mw:RunTimers() end
end
M.SelectPage("opt_castbar")
Settle()
local entry = assert(M.cache.opt_castbar)
for _, section in pairs(entry.sections or {}) do M.Widgets.EnsureSectionContent(section) end
Settle()
local duration = assert(controls["general.castbarInterruptFeedbackDuration"], "missing real duration control")
local function Set(value)
    duration.set(value)
    M.ApplyService.Flush()
    Settle()
    assert(env.MSUF_DB.general.castbarInterruptFeedbackDuration == value, "duration control did not save")
    assert(castbars.Utils.GetInterruptFeedbackDuration() == value, "flush error left runtime interrupt duration stale")
end
return env, castbars, Config, M, duration, Set
end
local failures = {}
local function Check(name, run)
    local ok, err = pcall(run)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
Check("escaped OnSettingsChanged", function()
    local env, castbars, Config, M, duration, Set = NewWorld()
    Set(4.4)
    local sync = castbars.Anchors.UpdateCastbarWidthSourceSync
    castbars.Anchors.UpdateCastbarWidthSourceSync = function() error("settings failure") end
    local ok, err = pcall(env.MSUF_Castbars_OnSettingsChanged, "profile")
    castbars.Anchors.UpdateCastbarWidthSourceSync = sync
    assert(not ok and tostring(err):find("settings failure", 1, true), "error did not escape")
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 1.1
    env.MSUF_Castbars_OnSettingsChanged("profile")
    env.MSUF_ApplyAllCastbarsAndSync()
    assert(castbars.Utils.GetInterruptFeedbackDuration() == 1.1, "settings error left runtime at 4.4")
end)
Check("escaped ApplyAllCastbarsAndSync", function()
    local env, castbars, Config, M, duration, Set = NewWorld()
    Set(4.4)
    local anchor = castbars.Anchors.ReanchorPlayerCastBarBase
    castbars.Anchors.ReanchorPlayerCastBarBase = function() error("apply failure") end
    local ok, err = pcall(env.MSUF_ApplyAllCastbarsAndSync)
    castbars.Anchors.ReanchorPlayerCastBarBase = anchor
    assert(not ok and tostring(err):find("apply failure", 1, true), "error did not escape")
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 1.1
    env.MSUF_ApplyAllCastbarsAndSync()
    assert(castbars.Utils.GetInterruptFeedbackDuration() == 1.1, "apply error left runtime at 4.4")
end)
Check("reentrant flush", function()
    local env, castbars, Config, M, duration, Set = NewWorld()
    Set(1.5)
    local applyAll, compile = env.MSUF_ApplyAllCastbarsAndSync, Config.Compile
    local counts, entered, total = {}, false, 0
    Config.Compile = function(...)
        local revision = Config.revision or 0
        counts[revision] = (counts[revision] or 0) + 1
        total = total + 1
        return compile(...)
    end
    env.MSUF_ApplyAllCastbarsAndSync = function(...)
        if not entered then
            entered = true
            duration.set(3.3)
            M.ApplyService.RequestCastbars("inner")
            M.ApplyService.Flush()
        end
        return applyAll(...)
    end
    duration.set(2.5)
    M.ApplyService.RequestCastbars("outer")
    local ok, err = pcall(M.ApplyService.Flush)
    env.MSUF_ApplyAllCastbarsAndSync = applyAll
    Config.Compile = compile
    assert(ok, err)
    assert(entered, "flush did not reenter")
    for revision, count in pairs(counts) do
        assert(count == 1, "revision " .. revision .. " compiled " .. count .. " times (total " .. total .. ")")
    end
    assert(castbars.Utils.GetInterruptFeedbackDuration() == 3.3, "reentry lost the newer setting")
    Set(1.1)
end)
Check("profile apply error before castbar fanout", function()
    local env, castbars, Config = NewWorld()
    Config.Read()
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 1.1
    local scale = env.MSUF_ApplyCurrentProfileGlobalUiScale
    env.MSUF_ApplyCurrentProfileGlobalUiScale = function() error("profile scale failure") end
    local ok, err = pcall(env.MSUF.ProfileRuntime.Apply, "profile")
    env.MSUF_ApplyCurrentProfileGlobalUiScale = scale
    assert(not ok and tostring(err):find("profile scale failure", 1, true), "profile error did not escape")
    assert(Config.Read("player").general.castbarInterruptFeedbackDuration == 1.1, "profile error kept the old snapshot")
end)
Check("lazy writes and repeated unit readers", function()
    local env, castbars, Config = NewWorld()
    Config.Read()
    env.MSUF_DB.general.castbarShowGlow = true
    Config.Compile()
    local count, compile = 0, Config.Compile
    Config.Compile = function(...) count = count + 1 return compile(...) end
    local record = Config.Read("target")
    env.MSUF_DB.general.castbarShowGlow = false
    Config.Invalidate()
    Config.EnsureSource()
    assert(count == 0 and record.showGlow, "write compiled eagerly")
    for _ = 1, 3 do
        for _, unit in ipairs({ "player", "target", "focus", "boss1", "boss5", "arena1", "arena5" }) do
            local current = Config.Read(unit)
            assert(current.revision == Config.revision and not current.showGlow, "reader kept an old record")
        end
        Config.Read()
    end
    assert(count == 1, "readers compiled more than once per revision")
    Config.Compile = compile
end)
Check("Copy To error before apply", function()
    local env, castbars, Config, M = NewWorld()
    env.MSUF_DB.player.showInterrupt = true
    env.MSUF_DB.target.showInterrupt = false
    env.MSUF_DB.general.castbarPlayerBarHeight = 47
    Config.Compile()
    local sync = env.MSUF_UpdateCastbarWidthSourceSync
    env.MSUF_UpdateCastbarWidthSourceSync = function() error("copy width failure") end
    local ok, err = pcall(M.UnitPage.CopyUnitSettings, "player", "target", { castbar = true }, nil, true)
    env.MSUF_UpdateCastbarWidthSourceSync = sync
    assert(not ok and tostring(err):find("copy width failure", 1, true), "copy error did not escape")
    local target = Config.Read("target")
    assert(target.unit.showInterrupt and target.general.castbarTargetBarHeight == 47, "copy error kept old settings")
end)
Check("legacy backend writes", function()
    local env, castbars, Config = NewWorld()
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        castbars.Backend.Set(unit, "MSUF")
    end
    Config.Read()
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local key = castbars.Backend.LegacyEnableKey(unit)
        env.MSUF_DB.general[key] = false
        env.MSUF_Castbars_OnSettingsChanged("legacy")
        assert(Config.Read(unit).backend == (unit == "player" and "BLIZZARD" or "HIDE"), "legacy disable was lost")
        env.MSUF_DB.general[key] = true
        env.MSUF_Castbars_OnSettingsChanged("legacy")
        assert(Config.Read(unit).backend == "MSUF", "legacy enable was lost")
    end
end)
Check("page reset error before runtime apply", function()
    local env, castbars, Config, M = NewWorld()
    local factory = env.MSUF.ProfileFields.CopySnapshot(env.MSUF_DB)
    factory.general.castbarInterruptFeedbackDuration = 1.1
    env.MSUF.MSUF_CreateFactoryDefaultProfile = function()
        return env.MSUF.ProfileFields.CopySnapshot(factory)
    end
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 4.4
    Config.Compile()
    local clear = env.MSUF_ClearResolvedStatusbarTextureCache
    env.MSUF_ClearResolvedStatusbarTextureCache = function() error("reset purge failure") end
    local ok, err = pcall(M.ResetPageToDefaults, "opt_castbar")
    env.MSUF_ClearResolvedStatusbarTextureCache = clear
    assert(not ok and tostring(err):find("reset purge failure", 1, true), "reset error did not escape")
    assert(env.MSUF_DB.general.castbarInterruptFeedbackDuration == 1.1, "reset did not write factory settings")
    assert(Config.Read("player").general.castbarInterruptFeedbackDuration == 1.1, "reset error kept the old snapshot")
end)
Check("history restore error before runtime apply", function()
    local env, castbars, Config, M = NewWorld()
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 1.1
    local snapshot = M.CaptureGuidedTourRestorePoint()
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 4.4
    Config.Compile()
    local external = env.MSUF.ProfileFields.ApplyExternal
    env.MSUF.ProfileFields.ApplyExternal = function() error("history external failure") end
    local ok, err = pcall(M.RestoreGuidedTourRestorePoint, snapshot)
    env.MSUF.ProfileFields.ApplyExternal = external
    assert(not ok and tostring(err):find("history external failure", 1, true), "history error did not escape")
    assert(env.MSUF_DB.general.castbarInterruptFeedbackDuration == 1.1, "history did not restore settings")
    assert(Config.Read("player").general.castbarInterruptFeedbackDuration == 1.1, "history error kept the old snapshot")
end)
Check("public visual and texture updates", function()
    local env, castbars, Config = NewWorld()
    for _, name in ipairs({ "MSUF_UpdateCastbarVisuals_Immediate", "MSUF_UpdateCastbarTextures_Immediate",
        "MSUF_ApplyCastbarVisualsForUnit", "MSUF_BumpCastbarStyleRevision" }) do
        env.MSUF_DB.general.castbarInterruptFeedbackDuration = 4.4
        Config.Compile()
        env.MSUF_DB.general.castbarInterruptFeedbackDuration = 1.1
        if name == "MSUF_ApplyCastbarVisualsForUnit" then env[name]("player") else env[name]() end
        assert(Config.Read("player").general.castbarInterruptFeedbackDuration == 1.1, name .. " kept the old snapshot")
    end
end)
Check("Edit Mode undo error before castbar apply", function()
    local env, castbars, Config = NewWorld()
    local util = env.MSUF_EM2.Util
    util.SharedHistoryService = function() end
    util.ApplyAllSettingsSafe = function() error("undo apply failure") end
    local loadUndo = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Undo.lua"))
    setfenv(loadUndo, env)
    loadUndo("MidnightSimpleUnitFrames", env.MSUF)
    local undo = env.MSUF_EM2.Undo
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 1.1
    undo.BeforeChange("general", "layout")
    env.MSUF_DB.general.castbarInterruptFeedbackDuration = 4.4
    Config.Compile()
    local ok, err = pcall(undo.DoUndo)
    assert(not ok and tostring(err):find("undo apply failure", 1, true), "undo error did not escape")
    assert(env.MSUF_DB.general.castbarInterruptFeedbackDuration == 1.1, "undo did not restore settings")
    assert(Config.Read("player").general.castbarInterruptFeedbackDuration == 1.1, "undo error kept the old snapshot")
end)
Check("Copy To error during backend normalization", function()
    local env, castbars, Config, M = NewWorld()
    env.MSUF_DB.player.showInterrupt = true
    env.MSUF_DB.target.showInterrupt = false
    Config.Compile()
    local normalize = env.MSUF_NormalizeCastbarBackendForUnit
    env.MSUF_NormalizeCastbarBackendForUnit = function() error("copy backend failure") end
    local ok, err = pcall(M.UnitPage.CopyUnitSettings, "player", "target", { castbar = true }, nil, true)
    env.MSUF_NormalizeCastbarBackendForUnit = normalize
    assert(not ok and tostring(err):find("copy backend failure", 1, true), "copy backend error did not escape")
    assert(Config.Read("target").unit.showInterrupt, "copy backend error kept old unit settings")
end)
for _, failure in ipairs(failures) do print(failure) end
assert(#failures == 0, #failures .. " revision recovery regressions")
print("castbar_revision_recovery_smoke: ok")
