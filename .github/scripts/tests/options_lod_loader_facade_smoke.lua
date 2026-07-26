-- Contract: the core Options facade owns no passive work. Core slash commands
-- remain core-only, while every cold Options entry performs one synchronous
-- LoD load followed by one real dispatch.
local root = arg and arg[1] or "."
local loaderPath = root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_OptionsLoader.lua"
local finalizerPath = root .. "/MidnightSimpleUnitFrames_Options/MSUF_OptionsLOD_Finalize.lua"
local apiPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_API.lua"
local realPrint = print

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function Contains(value, needle, message)
  Check(type(value) == "string" and value:find(needle, 1, true) ~= nil,
    (message or "text missing") .. ": expected " .. tostring(needle)
      .. " in " .. tostring(value))
end

local function Read(path)
  local file = assert(io.open(path, "rb"), path)
  local text = file:read("*a")
  file:close()
  return text
end

local source = Read(loaderPath)
local apiSource = Read(apiPath)
for _, forbidden in ipairs({
  "CreateFrame", "RegisterEvent", "RegisterUnitEvent", "HookScript",
  "SetScript(\"OnUpdate", "NewTicker", "C_Timer",
}) do
  Check(not source:find(forbidden, 1, true),
    "zero-idle loader contains passive work: " .. forbidden)
end
Check(apiSource:find('SlashCmdList["MSUFOPTIONS"] == MSUF.OptionsLODMSUFOptionsStub', 1, true),
  "warm /msufoptions does not replace the owned loader dispatcher")
Check(apiSource:find("MSUF.OptionsLODMSUFOptionsStub = nil", 1, true),
  "warm /msufoptions leaves a stale loader marker")

local forwardedGlobals = {
  "MSUF2_Open",
  "MSUF2_Toggle",
  "MSUF_OpenStandaloneOptionsWindow",
  "MSUF_ShowStandaloneOptionsWindow",
  "MSUF_HideStandaloneOptionsWindow",
  "MSUF_OpenOptionsMenu",
  "MSUF_OpenPage",
  "MSUF_SwitchMirrorPage",
  "MSUF_GetCurrentMirrorPage",
  "MSUF_GetMirrorPages",
  "MSUF_OpenExactSettingControl",
  "MSUF_OpenExactColorSettingPicker",
  "MSUF_OpenExactCatalogControl",
  "MSUF_StartGuidedTour",
  "MSUF_ResumeGuidedTour",
}

local requiredMenuFunctions = {
  "Open",
  "Toggle",
  "SelectPage",
  "OpenExactSettingControl",
  "OpenExactColorSettingPicker",
  "OpenExactCatalogControl",
  "ShowLocaleReloadRequired",
}

local function NewHarness(options)
  options = options or {}
  for _, name in ipairs(forwardedGlobals) do _G[name] = nil end
  _G.MSUF_EnsureOptionsLoaded = nil
  _G.MSUF_IsOptionsLoaded = nil
  _G.SLASH_MSUF2OPTIONS1 = nil
  _G.SLASH_MSUFOPTIONS1 = nil
  _G.SLASH_MSUFMENUCHECK1 = nil
  _G.SlashCmdList = {}

  local counters = {
    loads = 0,
    frames = 0,
    timers = 0,
    hooks = 0,
    locks = 0,
    prints = 0,
    globalCalls = 0,
    menuCalls = 0,
    localeCalls = 0,
    slashCalls = 0,
    menuCheckCalls = 0,
  }
  local apiLoading, apiLoaded, combat = false, false, false
  local private = {}
  local main = {
    ExportPublic = function(name, value)
      _G[name] = value
      return value
    end,
  }
  local preexistingOwnedGlobal
  local preexistingOwnedMenu
  if options.preexistingOwned then
    preexistingOwnedGlobal = function() return "foreign-global" end
    preexistingOwnedMenu = function() return "foreign-menu" end
    for _, name in ipairs(forwardedGlobals) do _G[name] = preexistingOwnedGlobal end
    main.MSUF2 = {
      Open = preexistingOwnedMenu,
      Toggle = preexistingOwnedMenu,
      SelectPage = preexistingOwnedMenu,
      ShowLocaleReloadRequired = preexistingOwnedMenu,
    }
  end
  local commandWords = {}
  local commandOrder = {}
  local function CoreCommand(name)
    local entry = {
      name = name,
      group = "general",
      usage = "/msuf " .. name,
      help = name,
      core = true,
      run = function(_, fullMessage)
        counters.lastSlash = fullMessage
        return "slash:" .. tostring(fullMessage)
      end,
    }
    commandWords[name] = entry
    commandOrder[#commandOrder + 1] = entry
  end
  CoreCommand("help")
  CoreCommand("version")
  main.SlashCommands = {
    byWord = commandWords,
    order = commandOrder,
    Register = function(entry)
      local words = { tostring(entry.name or ""):lower() }
      for i = 1, #(entry.aliases or {}) do
        words[#words + 1] = tostring(entry.aliases[i]):lower()
      end
      for i = 1, #words do
        if commandWords[words[i]] then return false end
      end
      for i = 1, #words do commandWords[words[i]] = entry end
      commandOrder[#commandOrder + 1] = entry
      return true
    end,
    Get = function(word)
      return commandWords[tostring(word or ""):lower()]
    end,
    Dispatch = function(message)
      counters.slashCalls = counters.slashCalls + 1
      counters.lastSlash = message
      local word, rest = tostring(message or ""):match("^(%S+)%s*(.-)$")
      local entry = word and commandWords[word:lower()] or nil
      if entry then return entry.run(rest or "", message) end
      return "slash:" .. tostring(message)
    end,
  }
  _G.MSUF_NS = main
  _G.MSUF2 = main.MSUF2
  _G.CreateFrame = function()
    counters.frames = counters.frames + 1
    error("Options loader created a frame")
  end
  _G.C_Timer = {
    After = function() counters.timers = counters.timers + 1 end,
    NewTimer = function() counters.timers = counters.timers + 1 end,
    NewTicker = function() counters.timers = counters.timers + 1 end,
  }
  _G.hooksecurefunc = function() counters.hooks = counters.hooks + 1 end
  _G.InCombatLockdown = function() return combat end
  _G.MSUF_IsConfigCombatLocked = nil
  _G.MSUF_ShowConfigCombatLockMessage = function()
    counters.locks = counters.locks + 1
  end
  _G.print = function(message)
    counters.prints = counters.prints + 1
    counters.lastPrint = tostring(message)
  end
  _G.C_AddOns = {
    IsAddOnLoaded = function(name)
      Check(name == "MidnightSimpleUnitFrames_Options", "loader queried wrong addon")
      counters.loadedQueries = (counters.loadedQueries or 0) + 1
      return apiLoading, apiLoaded
    end,
  }

  local function InstallCompleteOptions(omitMenuFunction)
    for _, name in ipairs(forwardedGlobals) do
      _G[name] = function(value)
        counters.globalCalls = counters.globalCalls + 1
        counters.lastGlobal = name
        counters.lastPage = value
        return "global:" .. tostring(value)
      end
    end

    local menu = main.MSUF2
    for _, name in ipairs(requiredMenuFunctions) do
      if name ~= omitMenuFunction then
        if name == "Open" then
          menu[name] = function(page)
            counters.menuCalls = counters.menuCalls + 1
            counters.lastMenuPage = page
            return "menu:" .. tostring(page)
          end
        elseif name == "ShowLocaleReloadRequired" then
          menu[name] = function(locale)
            counters.localeCalls = counters.localeCalls + 1
            counters.lastLocale = locale
            return "locale:" .. tostring(locale)
          end
        else
          menu[name] = function() return name end
        end
      end
    end
    menu.Theme = {}
    menu.Widgets = {}
    menu.ApplyService = {}
    menu.SearchBridge = {}
    menu.pages = {}
    if not options.keepDeferred then
      for _, spec in ipairs(main.OptionsLODCommandSpecs or {}) do
        local entry = main.SlashCommands.Get(spec.name)
        if entry and entry._msufOptionsLODDeferred == true then
          entry._msufOptionsLODDeferred = nil
          entry.run = function(_, fullMessage)
            counters.lastSlash = fullMessage
            return "slash:" .. tostring(fullMessage)
          end
        end
      end
    end
    _G.SlashCmdList.MSUFMENUCHECK = function(message)
      counters.menuCheckCalls = counters.menuCheckCalls + 1
      counters.lastMenuCheck = message
      return "menucheck:" .. tostring(message)
    end
  end

  local function RunFinalizer()
    assert(loadfile(finalizerPath))("MidnightSimpleUnitFrames_Options", private)
  end

  _G.MSUF_EnsureAddonLoaded = function(name)
    Equal(name, "MidnightSimpleUnitFrames_Options", "loaded addon name")
    counters.loads = counters.loads + 1
    apiLoading, apiLoaded = true, false

    if options.reenter and counters.loads == 1 then
      counters.reentrantResult = _G.MSUF_EnsureOptionsLoaded("nested-demand")
    end

    if options.loadMode == "throw" then
      apiLoading = false
      error("synthetic load failure")
    end
    if options.loadMode == "incomplete" then
      apiLoading, apiLoaded = false, true
      return true
    end
    if options.loadMode == "false" then
      apiLoading, apiLoaded = false, false
      return false
    end

    InstallCompleteOptions()
    apiLoading, apiLoaded = false, true
    RunFinalizer()
    return true
  end

  assert(loadfile(loaderPath))("MidnightSimpleUnitFrames", main)
  Equal(counters.loads, 0, "loader eagerly loaded Options")
  Equal(counters.frames, 0, "loader idle frame count")
  Equal(counters.timers, 0, "loader idle timer count")
  Equal(counters.hooks, 0, "loader idle hook count")

  return {
    main = main,
    menu = main.MSUF2,
    private = private,
    counters = counters,
    InstallCompleteOptions = InstallCompleteOptions,
    RunFinalizer = RunFinalizer,
    SetAddonState = function(loading, loaded)
      apiLoading, apiLoaded = loading == true, loaded == true
    end,
    SetCombat = function(value) combat = value == true end,
    preexistingOwnedGlobal = preexistingOwnedGlobal,
    preexistingOwnedMenu = preexistingOwnedMenu,
  }
end

local ownershipCase = NewHarness({ preexistingOwned = true })
for _, name in ipairs(forwardedGlobals) do
  Check(_G[name] ~= ownershipCase.preexistingOwnedGlobal,
    "cold loader did not reclaim MSUF-owned global: " .. name)
end
for _, name in ipairs({ "Open", "Toggle", "SelectPage", "ShowLocaleReloadRequired" }) do
  Check(ownershipCase.menu[name] ~= ownershipCase.preexistingOwnedMenu,
    "cold loader did not reclaim MSUF2-owned method: " .. name)
end

local globalCase = NewHarness()
for _, name in ipairs(forwardedGlobals) do
  Check(type(_G[name]) == "function", "missing lazy global facade: " .. name)
end
Check(type(globalCase.menu.Open) == "function"
  and type(globalCase.menu.Toggle) == "function"
  and type(globalCase.menu.SelectPage) == "function"
  and type(globalCase.menu.ShowLocaleReloadRequired) == "function",
  "missing lazy MSUF2 method facades")
Equal(_G.SLASH_MSUF2OPTIONS1, "/msuf", "cold /msuf registration")
Equal(_G.SLASH_MSUFOPTIONS1, "/msufoptions", "cold /msufoptions registration")
Equal(_G.SLASH_MSUFMENUCHECK1, "/msufmenucheck", "cold /msufmenucheck registration")
for _, name in ipairs({ "edit", "lock", "search", "tour", "locale", "versiontest", "firstload" }) do
  local entry = globalCase.main.SlashCommands.Get(name)
  Check(type(entry) == "table" and entry._msufOptionsLODDeferred == true,
    "cold help metadata missing deferred command: " .. name)
end
Equal(#globalCase.main.SlashCommands.order, 9,
  "cold help metadata changed command ordering/count")

Equal(_G.MSUF_OpenStandaloneOptionsWindow("profiles"), "global:profiles",
  "cold global facade return")
Equal(globalCase.counters.loads, 1, "cold global facade load count")
Equal(globalCase.counters.globalCalls, 1, "cold global facade dispatch count")
Equal(_G.MSUF_OpenStandaloneOptionsWindow("unit"), "global:unit",
  "warm global implementation return")
Equal(globalCase.counters.loads, 1, "warm global facade reloaded Options")
Equal(globalCase.counters.globalCalls, 2, "warm global implementation dispatch count")

local menuCase = NewHarness()
Equal(menuCase.menu.Open("auras"), "menu:auras", "cold MSUF2.Open return")
Equal(menuCase.counters.loads, 1, "cold MSUF2.Open load count")
Equal(menuCase.counters.menuCalls, 1, "cold MSUF2.Open dispatch count")

local localeCase = NewHarness()
Equal(localeCase.menu.ShowLocaleReloadRequired("deDE"), "locale:deDE",
  "cold locale reload facade return")
Equal(localeCase.counters.loads, 1, "cold locale reload facade load count")
Equal(localeCase.counters.localeCalls, 1, "cold locale reload facade dispatch count")
Equal(localeCase.menu.ShowLocaleReloadRequired("enUS"), "locale:enUS",
  "warm locale reload implementation return")
Equal(localeCase.counters.loads, 1, "warm locale reload facade reloaded Options")
Equal(localeCase.counters.localeCalls, 2, "warm locale reload dispatch count")

local coreSlashCase = NewHarness()
Equal(_G.SlashCmdList.MSUF2OPTIONS("version"), "slash:version",
  "cold /msuf version dispatch")
Equal(coreSlashCase.counters.loads, 0, "cold /msuf version loaded Options")
Equal(coreSlashCase.counters.slashCalls, 1, "cold /msuf version dispatch count")

local helpSlashCase = NewHarness()
Equal(_G.SlashCmdList.MSUF2OPTIONS("help"), "slash:help",
  "cold /msuf help redispatch")
Equal(helpSlashCase.counters.loads, 1, "cold /msuf help load count")
Equal(helpSlashCase.counters.slashCalls, 1, "cold /msuf help dispatch count")

local slashCase = NewHarness()
Equal(_G.SlashCmdList.MSUF2OPTIONS("search portrait"), "slash:search portrait",
  "cold /msuf redispatch")
Equal(slashCase.counters.loads, 1, "cold /msuf load count")
Equal(slashCase.counters.slashCalls, 1, "cold /msuf dispatch count")

local optionsSlashCase = NewHarness()
Equal(_G.SlashCmdList.MSUFOPTIONS(""), "slash:",
  "cold /msufoptions redispatch")
Equal(optionsSlashCase.counters.loads, 1, "cold /msufoptions load count")
Equal(optionsSlashCase.counters.slashCalls, 1, "cold /msufoptions dispatch count")

local menuCheckCase = NewHarness()
Equal(_G.SlashCmdList.MSUFMENUCHECK("all"), "menucheck:all",
  "cold /msufmenucheck redispatch")
Equal(menuCheckCase.counters.loads, 1, "cold /msufmenucheck load count")
Equal(menuCheckCase.counters.menuCheckCalls, 1, "cold /msufmenucheck dispatch count")

-- C_AddOns.IsAddOnLoaded returns (loadedOrLoading, loaded) on current clients.
-- Readiness must still require the finalizer marker.
local addonStateCase = NewHarness()
Equal(_G.MSUF_IsOptionsLoaded(), false, "cold two-return addon state")
addonStateCase.SetAddonState(true, false)
Equal(_G.MSUF_IsOptionsLoaded(), false, "loading state reported ready without finalizer")
addonStateCase.main.OptionsLODReady = true
Equal(_G.MSUF_IsOptionsLoaded(), true, "first-return loading state ignored")
addonStateCase.SetAddonState(false, true)
Equal(_G.MSUF_IsOptionsLoaded(), true, "second-return loaded state ignored")
Equal(_G.MSUF_EnsureOptionsLoaded("already-ready"), true,
  "already-ready two-return addon state")
Equal(addonStateCase.counters.loads, 0, "already-ready state reloaded Options")

local reentrantCase = NewHarness({ reenter = true })
Equal(_G.MSUF_EnsureOptionsLoaded("outer-demand"), true,
  "outer reentrant load result")
Equal(reentrantCase.counters.reentrantResult, false,
  "nested reentrant load was not blocked")
Equal(reentrantCase.counters.loads, 1, "reentrant path started a second load")

local thrownCase = NewHarness({ loadMode = "throw" })
Equal(_G.MSUF_EnsureOptionsLoaded("throw-test"), false,
  "throwing addon load result")
Equal(thrownCase.counters.loads, 1, "throwing addon load count")
Equal(thrownCase.counters.prints, 1, "throwing addon load error count")
Contains(thrownCase.counters.lastPrint, "synthetic load failure",
  "throwing addon load error detail")
Equal(thrownCase.main.OptionsLODReady, nil, "throwing addon load marked ready")

local incompleteCase = NewHarness({ loadMode = "incomplete" })
Equal(_G.MSUF_EnsureOptionsLoaded("incomplete-test"), false,
  "incomplete addon load result")
Equal(incompleteCase.counters.loads, 1, "incomplete addon load count")
Equal(incompleteCase.counters.prints, 1, "incomplete addon load error count")
Contains(incompleteCase.counters.lastPrint, "incomplete load",
  "incomplete addon load error detail")
Equal(incompleteCase.main.OptionsLODReady, nil, "incomplete addon load marked ready")

local finalizerSuccessCase = NewHarness()
finalizerSuccessCase.InstallCompleteOptions()
finalizerSuccessCase.SetAddonState(false, true)
finalizerSuccessCase.RunFinalizer()
Equal(finalizerSuccessCase.main.OptionsLODReady, true, "finalizer success readiness")
Equal(finalizerSuccessCase.main.OptionsLODLoadError, nil, "finalizer success error")
Equal(finalizerSuccessCase.main.OptionsLODLoadCount, 1, "finalizer success count")
Equal(finalizerSuccessCase.private.OptionsLODReady, true,
  "finalizer private namespace readiness")
Equal(_G.MSUF_IsOptionsLoaded(), true, "finalizer success public readiness")

local finalizerMissingCase = NewHarness()
finalizerMissingCase.InstallCompleteOptions("ShowLocaleReloadRequired")
finalizerMissingCase.SetAddonState(false, true)
finalizerMissingCase.RunFinalizer()
Equal(finalizerMissingCase.main.OptionsLODReady, nil,
  "missing finalizer API marked ready")
Equal(finalizerMissingCase.main.OptionsLODLoadError,
  "MSUF2.ShowLocaleReloadRequired missing", "missing finalizer API error")
Equal(finalizerMissingCase.main.OptionsLODLoadCount, nil,
  "missing finalizer API incremented load count")
Equal(_G.MSUF_IsOptionsLoaded(), false, "missing finalizer API public readiness")

local finalizerDeferredCase = NewHarness({ keepDeferred = true })
finalizerDeferredCase.InstallCompleteOptions()
finalizerDeferredCase.SetAddonState(false, true)
finalizerDeferredCase.RunFinalizer()
Equal(finalizerDeferredCase.main.OptionsLODReady, nil,
  "deferred slash finalizer marked ready")
Equal(finalizerDeferredCase.main.OptionsLODLoadError,
  "slash command edit still deferred", "deferred slash finalizer error")
Equal(_G.MSUF_IsOptionsLoaded(), false, "deferred slash public readiness")

local combatCase = NewHarness()
combatCase.SetCombat(true)
Equal(_G.SlashCmdList.MSUF2OPTIONS("version"), "slash:version",
  "combat core /msuf version dispatch")
Equal(_G.SlashCmdList.MSUF2OPTIONS("help"), "slash:help",
  "combat core /msuf help dispatch")
Equal(combatCase.counters.loads, 0, "combat core slash loaded Options")
Equal(combatCase.counters.locks, 0, "combat core slash showed lock feedback")
Equal(_G.SlashCmdList.MSUF2OPTIONS("search portrait"), false,
  "combat Options /msuf command result")
Equal(_G.SlashCmdList.MSUFOPTIONS(""), false,
  "combat /msufoptions result")
Equal(combatCase.counters.loads, 0, "combat Options slash loaded Options")
Equal(combatCase.counters.slashCalls, 3,
  "combat blocked Options slash dispatched")
Equal(combatCase.counters.locks, 2, "combat Options slash lock feedback")

local combatFacadeCase = NewHarness()
combatFacadeCase.SetCombat(true)
Equal(_G.MSUF_OpenStandaloneOptionsWindow("home"), false,
  "combat-blocked facade result")
Equal(combatFacadeCase.counters.loads, 0, "combat-blocked facade loaded Options")
Equal(combatFacadeCase.counters.globalCalls, 0, "combat-blocked facade dispatched")
Equal(combatFacadeCase.counters.locks, 1, "combat-blocked facade lock feedback")

_G.print = realPrint
realPrint("PASS: zero-idle Options loader, facades, slash routing, failures, and finalizer contract")
