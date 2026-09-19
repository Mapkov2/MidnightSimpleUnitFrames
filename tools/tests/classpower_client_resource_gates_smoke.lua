-- Real client boot, then the real preview catalog, behavior builder and search.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local pagePath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"
local function Read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local legacyKeys = { druid_feral = true, rogue_combo = true }
local mistsKeys = { deathknight_runes = true, druid_feral = true, druid_balance = true,
    mage_arcane = true, monk_windwalker = true, paladin_holy_power = true, priest_shadow = true,
    rogue_combo = true, warlock_soul_shards = true, warlock_destruction = true, warlock_demonic_fury = true }
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.message))
    local ns, env = world.core, world.env
    local client, M = ns.Client, ns.MSUF2
    local modern, mists = flavor == "Mainline", flavor == "Mists"
    local expected = mists and mistsKeys or legacyKeys
    local count = 0
    for key, spec in pairs(M.ClassPowerPreviewSpecs) do
        count = count + 1
        assert(modern or expected[key], flavor .. ": unavailable preview " .. key)
        assert(client.SupportsClassResource(spec.token or "NO_CLASS_BAR"), flavor .. ": unsupported preview token")
    end
    assert(count == (modern and 22 or mists and 11 or 2), flavor .. ": preview count " .. count)
    assert(#M.ClassPowerPreviewSpecValues == count, "dropdown/map mismatch")
    if not modern then
        for key in pairs(expected) do assert(M.ClassPowerPreviewSpecs[key], flavor .. ": missing " .. key) end
        local rogue = M.ClassPowerPreviewSpecs.rogue_combo
        assert(rogue.segments == 5 and rogue.chargedSlots == nil, "Retail combo pips leaked")
        M.SetClassPowerPreviewSpecKey("evoker_augmentation_ebon")
        assert(M.GetClassPowerPreviewSpecKey() == "rogue_combo", "stale preview did not fall back")
    else
        assert(M.ClassPowerPreviewSpecs.rogue_combo.segments == 7)
        assert(M.ClassPowerPreviewSpecs.rogue_combo.chargedSlots[1])
    end
    if mists then
        assert(M.ClassPowerPreviewSpecs.priest_shadow.token == "SHADOW_ORBS")
        assert(M.ClassPowerPreviewSpecs.warlock_destruction.token == "BURNING_EMBERS")
        assert(M.ClassPowerPreviewSpecs.warlock_soul_shards.segments == 4)
        assert(M.ClassPowerPreviewSpecs.warlock_demonic_fury.token == "DEMONIC_FURY")
        assert(M.ClassPowerPreviewSpecs.druid_balance.enabled == true)
    end
    for _, item in ipairs(M.ColorsPage.COLOR_CP_TOKENS) do
        assert(client.SupportsClassResource(item.value), flavor .. ": unsupported resource color " .. item.value)
    end
    -- Capture exactly what Page:Controls gives the real widget builder.
    local offered = {}
    local AP = M.AdvancedPage
    local originalBuilder = AP.BuildTableControlSpecs
    AP.BuildTableControlSpecs = function(_, _, _, _, specs)
        local controls = {}
        for _, spec in ipairs(specs) do
            offered[spec[4]] = true
            controls[spec[1]] = env.CreateFrame("Frame")
        end
        return controls
    end
    local chunk = assert(loadstring(Read(pagePath) .. "\nreturn Page", "@classpower-client-gates"))
    setfenv(chunk, env)
    local Page = chunk("MidnightSimpleUnitFrames_Options", ns)
    local page = setmetatable({ width = 1000, kinds = {}, ctx = {}, groups = { cp = {} }, refresh = function() end,
        b = { CollapsibleSection = function() return env.CreateFrame("Frame") end } }, { __index = Page })
    page:BuildClassBehavior()
    AP.BuildTableControlSpecs = originalBuilder
    local gated = { showChargedComboPoints = modern, runeShowTime = modern or mists,
        showSweepingStrikes = modern, showEleMaelstrom = modern, showEbonMight = modern,
        showShadowMana = modern, showGuardianIronfur = modern, guardianIronfurShowHashLines = modern,
        classPowerAnchorToCooldown = modern or flavor == "Forever" }
    for key, supported in pairs(gated) do
        assert((offered[key] == true) == supported, flavor .. ": wrong behavior control " .. key)
    end
    assert(offered.classPowerShowText and offered.classPowerFillReverse and offered.classPowerSmoothFill,
        "shared behavior controls disappeared")
    -- The controller configuration, not an emulated event rule.
    local K = env.MSUF_CP_CONST
    local config = env.MSUF_CP_CORE_BUILDERS.CONTROLLER_CONFIG({ CPConst = K, CPK = K.CPK, PT = K.PT,
        TIP = {}, PLAYER_CLASS = "ROGUE", NotSecret = function() return true end })
    local profile = config.GetModeEventProfile(K.CPK.MODE.SEGMENTED, K.PT.ComboPoints, false)
    assert(profile.pointCharge == modern, flavor .. ": charged-point event bound on wrong client")
    -- Run the real controller's charged-point refresh with an API that exists
    -- even on the older client. Availability of a global must not enable it.
    local chargedCalls = 0
    env.GetUnitChargedPowerPoints = function() chargedCalls = chargedCalls + 1; return {} end
    local controller = assert(loadstring(Read(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Controller.lua")
        .. "\nreturn RefreshChargedPoints, CP_RefreshEventBindings, CP, _cpDB, eventFrame", "@classpower-charged-client-gate"))
    setfenv(controller, env)
    env.__MSUF_ClassPower_Loaded = nil
    local refreshCharged, bindEvents, runtime, db, frame = controller("MidnightSimpleUnitFrames", ns)
    assert(refreshCharged and bindEvents)
    local before = chargedCalls
    refreshCharged()
    assert(chargedCalls - before == (modern and 1 or 0), flavor .. ": charged API queried on wrong client")
    runtime.visible = true
    runtime.powerType, runtime.renderMode = K.PT.ComboPoints, K.CPK.MODE.SEGMENTED
    runtime.CDMWidthSetEvents = function() end
    db.general = { perfLiteClassPowerEvents = false }
    bindEvents()
    assert(frame:IsEventRegistered("UNIT_POWER_POINT_CHARGE") == modern, flavor .. ": broad bindings leaked charged event")
    assert(frame:IsEventRegistered("RUNE_POWER_UPDATE") == (modern or mists), flavor .. ": broad bindings leaked rune event")
    -- Cold static index must not resurrect settings the page cannot construct.
    for key, query in pairs({ showEbonMight = "Ebon Might", runeShowTime = "rune time",
        showChargedComboPoints = "empowered combo", showGuardianIronfur = "Ironfur" }) do
        local found = false
        for _, rec in ipairs(M.Search._CoreAPI.SearchPages(query)) do
            if rec.exactTarget and rec.exactTarget.settingKey == "bars." .. key then found = true end
        end
        assert(found == gated[key], flavor .. ": wrong static search result for " .. key)
    end
    print("PASS " .. flavor .. ": " .. count .. " previews, behavior/color/search gates, charged event contract")
end
