-- Canonical requests agree with mirrors throughout the shipped cold and warm graph.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local mirrors = {
    editMode = "MSUF_UnitEditModeActive", all = "MSUF_PreviewTestMode",
    boss = "MSUF_BossTestMode", arena = "MSUF_ArenaTestMode",
    bossPage = "MSUF2_BossUnitframePreviewActive", arenaPage = "MSUF2_ArenaUnitframePreviewActive",
    unitPage = "MSUF_UnitPreviewActive",
}
local setters = {
    editMode = "SetEditMode", all = "SetAll", boss = "SetBoss", arena = "SetArena",
    bossPage = "SetBossPage", arenaPage = "SetArenaPage", unitPage = "SetUnitPage",
}
local checks = 0
local function Check(ok, message)
    assert(ok, flavor .. ": " .. message)
    checks = checks + 1
end
for _, warm in ipairs({ false, true }) do
    local world = World.New(root, flavor)
    world.env.secureexecuterange = function(list, callback, ...)
        for i = 1, #list do
            local ok, message = pcall(callback, i, list[i], ...)
            if not ok then world.env.geterrorhandler()(message) end
        end
    end
    if warm then world:Boot() else
        world:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root,
            World.CoreTOC(world.client.tocSuffix or flavor), "enUS", world.client.isForever and "camelot" or nil), world.core)
    end
    local failure = world:FirstFailure()
    Check(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    local env, ns = world.env, world.core
    local preview = assert(ns.UF.Preview, "real graph omitted UF.Preview")
    local state = preview.State
    local function Agreement()
        for key, name in pairs(mirrors) do Check(state[key] == env[name], name .. " diverged") end
    end
    Agreement()
    Check(env.MSUF_UnitPreviewActive == false and env.MSUF_PreviewTestMode == false
        and env.MSUF_BossTestMode == false and env.MSUF_ArenaTestMode == nil
        and env.MSUF2_BossUnitframePreviewActive == nil and env.MSUF2_ArenaUnitframePreviewActive == nil,
        "startup nil/false contract changed")
    -- The state table reserves every input at load: the first request of each one rehashes nothing.
    local firstUse = {}
    for _, setter in pairs(setters) do firstUse[#firstUse + 1] = preview[setter] end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for i = 1, #firstUse do firstUse[i](true) end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    Check(grown == 0, "first request of every input allocated " .. grown .. " KB")
    for i = 1, #firstUse do firstUse[i](nil) end
    Agreement()
    -- Output mirrors never authorize a request: a foreign write to one changes no decision.
    local animation = assert(ns.PreviewAnimation, "real graph omitted PreviewAnimation")
    env.MSUF_UnitEditModeActive = true
    animation.SetEnabled(true, "edit_mode")
    Check(state.unitPage ~= true and state.editMode ~= true, "foreign edit-mode mirror authorized the animation request")
    animation.SetEnabled(false, "edit_mode")
    env.MSUF_UnitEditModeActive = state.editMode
    local pages = env.MSUF2 and env.MSUF2.UnitPage
    for key, setter in pairs({ bossPage = "SetBossPagePreviewActive", arenaPage = "SetArenaPagePreviewActive" }) do
        if pages and pages[setter] then
            pages[setter](true)
            Check(state[key] == true, setter .. " did not request its page preview")
            env[mirrors[key]] = false
            pages[setter](true)
            Check(state[key] == true, setter .. " followed a foreign page mirror")
            pages[setter](false)
            Check(state[key] == nil, setter .. " did not clear its page request")
        end
    end
    Agreement()
    for key, setter in pairs(setters) do
        for _, value in ipairs({ true, false, true }) do
            local changed = state[key] ~= value
            Check(preview[setter](value) == changed, setter .. " change result")
            Check(state[key] == value and preview[setter](value) == false, setter .. " no-op")
            Agreement()
        end
        preview[setter](nil)
    end
    preview.SetBoss(true)
    preview.InitializeBoss()
    Check(state.boss == true, "boss boot initialization reset an existing request")
    local bootOK, bootMessage = world:LoadFile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua",
        "MidnightSimpleUnitFrames", ns)
    Check(bootOK, "actual boss boot caller failed: " .. tostring(bootMessage))
    Check(state.boss == true and env.MSUF_BossTestMode == true,
        "actual boss boot caller reset an existing request")
    env.MSUF_InitProfiles()
    for _, name in ipairs({ "MSUF_ApplyMsufScale", "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
        "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
        "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
        "MSUF_UpdateAllFonts_Immediate", "MSUF_ForceReanchorAllUnitFrames_Once" }) do env[name] = function() end end
    ns.UF.Apply = function() return true end
    if env.MSUF2 and env.MSUF2.ApplyService then env.MSUF2.ApplyService.Flush = function() return true end end
    ns.EventBus:Register("EDITMODE_STATE", "preview-agreement", Agreement)
    local em = ns.EditMode
    em.Open("player")
    Agreement()
    Check(state.editMode == true and state.unitPage == true, "entry did not request previews")
    -- A stale or foreign write to an output mirror never changes a request decision.
    env.MSUF_UnitPreviewActive = false
    env.MSUF_SyncAllUnitPreviews()
    Check(state.unitPage == true and state.all == true and state.boss == true and state.arena == true,
        "stale unit-page mirror changed the preview fan-out")
    env.MSUF_UnitPreviewActive = true
    em.Open("target")
    Agreement()
    em.Close("request-test")
    Agreement()
    Check(state.editMode == false and state.unitPage == false, "close left preview activation")
    em.Open("player", { provider = "ellesmere" })
    em.SuspendExternalPreview()
    Agreement()
    Check(state.editMode == false and em.IsActive(), "suspension changed session semantics")
    em.ResumeExternalPreview()
    Agreement()
    em.CancelAll()
    Agreement()
    em.Open("player")
    world:EnterCombat()
    Agreement()
    Check(state.editMode == false, "combat left edit preview active")
    world:LeaveCombat()
    Check(warm or world.optionsPaths == nil, "cold lifecycle loaded Options")
end
print("PASS canonical preview request lifecycle " .. flavor .. ": " .. checks .. " checks")
