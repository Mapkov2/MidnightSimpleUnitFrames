-- host_page_reset_provider_smoke.lua [repoRoot]
--
-- MSUF host API v1, Menu2 half: page-reset providers.
--
-- Loads the real Menu2 binding chain in its XML order (MSUF_Menu2_Bindings.lua,
-- _History.lua, _Reset.lua, MSUF_Menu2_PageResetProviders.lua) with the
-- real undo history, and drives the four page-reset functions:
--   * a registered provider owns its pages for all four functions;
--   * keys no provider owns behave exactly as with an empty registry;
--   * combat refuses (also when a confirmation is answered in combat);
--   * registering an id again replaces it, overlaps go to the latest
--     registration, RefreshPageResetProvider re-reads the pages;
--   * the provider's reset runs in one host history entry, and the host adds
--     no refresh, feedback or second entry of its own (the provider does those);
--   * prepare runs before the undo snapshot (a dormant state it loads is what
--     Undo restores, also inside an open menu session), finish after the
--     committed entry, historyLabel names it;
--   * a raising step is reported through Kernel/MSUF_Boundary.lua and never
--     leaves the history capturing; PLAYER_REGEN_DISABLED refuses before the
--     lockdown starts; a malformed provider leaves the others' pages alone;
--   * the confirmation uses Blizzard's generic dialog with nothing written to
--     StaticPopupDialogs;
--   * an old Suite's wrap of the four functions (MSUF-Suite a7aee25
--     MSUF_Suite_Options/Menu/Register.lua:193-256, verbatim) still works next
--     to the empty registry;
--   * the provider lookup is O(1) (same VM instruction count for 1 and 2000
--     registered pages) and allocates 0 KB per call.
--
-- Plain Lua 5.1 (loadstring, setfenv). Repo root as arg 1, default ".".

local root = ((arg and arg[1]) or "."):gsub("\\", "/"):gsub("/$", "")
local MENU2 = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
-- The core files the provider path uses, loaded as the core does: the step
-- boundary (Kernel/MSUF_Boundary.lua) and the host API's combat question.
local CORE = { root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua",
    root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua",
    root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_HostAPI.lua" }
local CHAIN = { "MSUF_Menu2_Bindings.lua", "MSUF_Menu2_Bindings_History.lua",
    "MSUF_Menu2_Bindings_Reset.lua", "MSUF_Menu2_PageResetProviders.lua" }

-- The Retail runner runs every smoke under .github/scripts/auras3_test_driver.lua,
-- whose loadfile injects shared contracts into the namespace it is given. This
-- harness builds its own, so it compiles the shipped sources directly.
local function LoadChunk(path)
    local handle = io.open(path, "rb")
    if not handle then return nil, path .. " is missing" end
    local source = handle:read("*a")
    handle:close()
    return loadstring(source, "@" .. path)
end

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[DeepCopy(key)] = DeepCopy(child) end
    return out
end

local function Show(value)
    if type(value) ~= "table" then return type(value) == "string" and ("%q"):format(value) or tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for index = 1, #keys do parts[index] = tostring(keys[index]) .. "=" .. Show(value[keys[index]]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local XML = io.open(MENU2 .. "MSUF_Menu2.xml", "rb"):read("*a")
do
    local last = 0
    for _, file in ipairs(CHAIN) do
        local at = XML:find('<Script file="' .. file .. '"/>', 1, true)
        Check(at and at > last, "MSUF_Menu2.xml must load " .. file .. " after the previous chain file")
        last = at
    end
end

-- One menu world: the real chain plus the host collaborators it reaches.
local function Boot()
    -- combat: the lockdown. regenEdge: PLAYER_REGEN_DISABLED is being
    -- dispatched (the player is flagged in combat, the lockdown not yet on).
    local world = { log = {}, combat = false, regenEdge = false, popupWrites = {}, shown = nil, frameShown = true }
    local function Log(text) world.log[#world.log + 1] = text end
    world.Log = Log
    local globals = {}
    for _, name in ipairs({ "type", "tonumber", "tostring", "pairs", "ipairs", "next", "error", "select",
        "string", "table", "math", "assert", "rawget", "rawset", "setmetatable", "getmetatable", "unpack", "pcall" }) do
        globals[name] = _G[name]
    end
    globals.print = function(...) Log("print " .. table.concat({ ... }, " ")) end
    globals.InCombatLockdown = function() return world.combat end
    globals.UnitAffectingCombat = function(unit) return unit == "player" and (world.combat or world.regenEdge) end
    -- MSUF.ReportError reports through the client's error handler.
    globals.geterrorhandler = function() return function(message) Log("error " .. tostring(message)) end end
    globals.C_Timer = {
        After = function(_, fn) Log("timer") fn() end,
        NewTimer = function(_, fn) Log("timer") fn() return { Cancel = function() end } end,
    }
    local profile = { general = { marker = 1 }, bars = {} }
    globals.MSUF_DB = profile
    globals.MSUF_ActiveProfile = "Default"
    globals.MSUF_GlobalDB = { profiles = { Default = profile }, char = {} }
    globals.MSUF_GetCharKey = function() return "Tester-Realm" end
    -- Notifiers the history module calls on Classic (Edit Mode and profile routing).
    globals.MSUF_EM_RefreshHistoryControls = function() end
    globals.MSUF_EM_RefreshAfterHistoryRestore = function() end
    globals.MSUF_ApplySpecProfileIfEnabled = function() end
    globals.YES, globals.NO = "Yes", "No"
    globals.StaticPopupDialogs = setmetatable({}, { __newindex = function(t, key, value)
        world.popupWrites[#world.popupWrites + 1] = key
        rawset(t, key, value)
    end })
    globals.StaticPopup_Show = function(which, text, _, data)
        Log("StaticPopup_Show " .. tostring(which) .. " " .. tostring(text) .. " " .. Show(data))
        world.shown = { which = which, text = text, data = data }
    end
    -- Blizzard_StaticPopup: GENERIC_CONFIRMATION formats data.text with its
    -- arguments on show, and a visible dialog with the same data is replaced.
    globals.StaticPopup_ShowCustomGenericConfirmation = function(data)
        local text = string.format(data.text, data.text_arg1, data.text_arg2)
        Log("generic " .. text)
        world.generic = { data = data, text = text, replaced = world.generic ~= nil and world.generic.data == data }
    end
    local env = setmetatable({}, { __index = globals, __newindex = globals })
    globals._G = env
    world.env, world.globals = env, globals

    local namespace = { MSUF2 = {}, Util = { InCombat = function() return world.combat end } }
    namespace.ExportPublic = function(name, value) globals[name] = value return value end
    for _, path in ipairs(CORE) do
        local chunk = assert(LoadChunk(path))
        setfenv(chunk, env)("MidnightSimpleUnitFrames", namespace)
    end
    local M = namespace.MSUF2
    M.KeySet = function(...) local out = {} for i = 1, select("#", ...) do out[select(i, ...)] = true end return out end
    M.KeySetFromWords = function(text) local out = {} for w in text:gmatch("%S+") do out[w] = true end return out end
    M.WordList = function(text) local out = {} for w in text:gmatch("%S+") do out[#out + 1] = w end return out end
    M.DeepCopy = DeepCopy
    M.ApplyService = {}
    M.Tr = function(text) return text end
    M.Format = function(text, ...) return string.format(text, ...) end
    M.IsConfigCombatLocked = function() return world.combat end
    M.MenuTimer = globals.C_Timer -- Classic's coalesced menu refresh reads it at load
    -- Classic reads the host's combat message at load; Retail defines its own.
    M.ShowConfigCombatLockMessage = function() Log("combatlock") end
    M.pages = { suite_alpha = { title = "Alpha" }, suite_beta = { title = "Beta" }, opt_bars = { title = "Bars" } }
    -- The host's own collaborators: any call is logged, so a provider reset
    -- that triggers a host refresh or host feedback shows up in the log.
    M.ShowStatusFeedback = function(text) Log("feedback " .. tostring(text)) end
    M.SetFixedPreviewExpandedPreference = function() Log("host:fixedPreview") end
    M.ApplyLocaleSelection = function() Log("host:locale") end
    M.InvalidatePage = function(key) Log("host:invalidate " .. tostring(key)) end
    M.SelectPage = function(key) Log("host:select " .. tostring(key)) end
    M.frame = { IsShown = function() return world.frameShown end }
    -- History bookkeeping that the window owns.
    M.MarkMenuDataDirty = function() end
    M.RepaintPageAfterDataChange = function() return true end
    -- The host's legacy named-dialog export (kept for old Suite builds) and
    -- its own prompts (Support.lua M.ShowPrompt, which writes nothing).
    M.InstallStaticPopup = function(key, spec)
        Log("InstallStaticPopup " .. key)
        if not globals.StaticPopupDialogs[key] then globals.StaticPopupDialogs[key] = spec end
        return globals.StaticPopupDialogs[key]
    end
    -- Support.lua's label shortener (UTF-8 aware there; the labels here are ASCII).
    M.ShortenUtf8 = function(text, limit)
        text = tostring(text or "")
        if #text <= limit then return text end
        return text:sub(1, math.max(1, limit - 3)) .. "..."
    end
    M.ShowPrompt = function(key, spec)
        Log("ShowPrompt " .. key .. " " .. tostring(spec.text))
        world.prompt = { key = key, spec = spec }
        return {}
    end
    for _, file in ipairs(CHAIN) do
        local chunk = assert(LoadChunk(MENU2 .. file))
        setfenv(chunk, env)("MidnightSimpleUnitFrames_Options", namespace)
    end
    world.M = M
    world.own = { M.PageHasReset, M.BuildPageResetWarning, M.ResetPageToDefaults, M.ShowPageResetConfirm }
    return world
end

local function Clear(world) for index = #world.log, 1, -1 do world.log[index] = nil end end
local function Logged(world) return table.concat(world.log, " | ") end
local function Has(world, prefix)
    for _, line in ipairs(world.log) do if line:sub(1, #prefix) == prefix then return true end end
    return false
end

-- A provider double in the shape the Suite registers.
local function Provider(world, pages, options)
    options = options or {}
    local provider = { resets = 0 }
    provider.pages = pages
    provider.allowed = true
    provider.result = true
    provider.text = options.text
    function provider.canReset(key) return provider.allowed end
    function provider.warning(key) return provider.text and (provider.text .. " " .. key) or nil end
    function provider.reset(key)
        provider.resets = provider.resets + 1
        provider.capturing = world.M.IsHistoryCapturing()
        world.Log("provider:reset " .. key)
        world.globals.MSUF_DB.general.marker = world.globals.MSUF_DB.general.marker + 1
        return provider.result
    end
    return provider
end

------------------------------------------------------------------------------
-- 1. API shape.
local world = Boot()
local M = world.M
Check(M.HOST_API_VERSION == 1, "M.HOST_API_VERSION must be 1")
Check(type(M.RegisterPageResetProvider) == "function" and type(M.RefreshPageResetProvider) == "function",
    "the registration functions are missing")
Check(type(M.PageResetProviders) == "table" and next(M.PageResetProviders) == nil, "the registry must start empty")

-- 2. Unowned keys: identical with an empty registry and with a provider on other pages.
local HOST_KEYS = { "uf_player", "opt_bars", "opt_fonts", "auras3_styling", "profiles", "gf_layout", "unknown", "" }
local function HostScript(w)
    local out = {}
    for _, key in ipairs(HOST_KEYS) do
        out[#out + 1] = key .. " has=" .. tostring(w.M.PageHasReset(key))
        out[#out + 1] = key .. " warn=" .. tostring(w.M.BuildPageResetWarning(key))
        -- The profile reset reloads the whole profile; its host path is not
        -- what this harness models.
        if key ~= "profiles" then out[#out + 1] = key .. " reset=" .. tostring(w.M.ResetPageToDefaults(key)) end
        out[#out + 1] = key .. " confirm=" .. tostring(w.M.ShowPageResetConfirm(key))
    end
    out[#out + 1] = "nil has=" .. tostring(w.M.PageHasReset(nil)) .. " reset=" .. tostring(w.M.ResetPageToDefaults(nil))
    w.combat = true
    out[#out + 1] = "combat reset=" .. tostring(w.M.ResetPageToDefaults("opt_bars"))
        .. " confirm=" .. tostring(w.M.ShowPageResetConfirm("opt_bars"))
    w.combat = false
    out[#out + 1] = "log=" .. Logged(w)
    out[#out + 1] = "popups=" .. table.concat(w.popupWrites, ",")
    out[#out + 1] = "db=" .. Show(w.globals.MSUF_DB)
    return table.concat(out, "\n")
end
local emptyRun = HostScript(Boot())
Check(emptyRun:find("uf_player has=true", 1, true) and emptyRun:find("unknown has=false", 1, true)
    and emptyRun:find("ShowPrompt MSUF2_PAGE_RESET_CONFIRM", 1, true),
    "the host's own page resets did not run in the harness:\n" .. emptyRun)
local populated = Boot()
populated.M.RegisterPageResetProvider("msuf-suite", Provider(populated, { suite_alpha = true, suite_beta = true }))
Clear(populated)
local populatedRun = HostScript(populated)
Check(populatedRun == emptyRun, "a provider on other pages changed the host's own keys:\n--- empty\n"
    .. emptyRun .. "\n--- populated\n" .. populatedRun)

-- 3. A provider owns its pages for all four functions.
world = Boot()
M = world.M
local toolbar = 0
M.RefreshToolbarPageReset = function() toolbar = toolbar + 1 end
local suite = Provider(world, { suite_alpha = true, suite_beta = true, ignored = false }, { text = "Suite warning" })
Check(M.RegisterPageResetProvider("msuf-suite", suite) == true and toolbar == 1,
    "registration must refresh the toolbar once")
Check(M.PageHasReset == world.own[1] and M.BuildPageResetWarning == world.own[2]
    and M.ResetPageToDefaults == world.own[3] and M.ShowPageResetConfirm == world.own[4],
    "registration must not wrap or replace the host's four functions")
Check(M.PageResetProviders.suite_alpha.source == suite and M.PageResetProviders.ignored == nil,
    "only pages marked true belong to the provider")
Check(M.PageHasReset("suite_alpha") == true and M.BuildPageResetWarning("suite_alpha") == "Suite warning suite_alpha",
    "the provider does not own PageHasReset/BuildPageResetWarning")
for _, value in ipairs({ false, 1, "yes" }) do
    suite.allowed = value
    Check(M.PageHasReset("suite_alpha") == false, "canReset must be exactly true, got " .. tostring(value))
    Check(M.ResetPageToDefaults("suite_alpha") == false and M.ShowPageResetConfirm("suite_alpha") == false
        and suite.resets == 0, "a page whose provider refuses must not reset or ask")
end
suite.allowed = true

-- Reset: one host history entry around the provider, nothing else from the host.
Clear(world)
local undoBefore = #(M.historyUndo or {})
Check(M.ResetPageToDefaults("suite_alpha") == true, "the provider reset failed")
Check(suite.resets == 1 and suite.capturing == true, "the provider reset did not run inside the host's history")
Check(#M.historyUndo == undoBefore + 1, "the provider reset must push exactly one history entry")
local entry = M.historyUndo[#M.historyUndo]
Check(entry.label == "Reset Alpha" and entry.source == "page:reset:suite_alpha",
    "history entry label/source: " .. tostring(entry.label) .. " / " .. tostring(entry.source))
Check(not Has(world, "host:") and not Has(world, "feedback") and not Has(world, "timer"),
    "the host refreshed or reported a provider reset itself: " .. Logged(world))
Check(world.globals.MSUF_DB.general.marker == 2, "the provider's change is missing")
Check(M.Undo() and world.globals.MSUF_DB.general.marker == 1, "the provider reset is not undoable")
-- A failed reset returns false and leaves no history entry.
suite.result = false
local depth = #M.historyUndo
Check(M.ResetPageToDefaults("suite_alpha") == false and #M.historyUndo == depth, "a failed provider reset left an entry")
suite.result = "yes"
Check(M.ResetPageToDefaults("suite_alpha") == false, "reset must report exactly true")
suite.result = true

-- Combat refuses before the provider runs, with the host's combat message.
world.combat = true
Clear(world)
local resets = suite.resets
Check(M.ResetPageToDefaults("suite_alpha") == false and M.ShowPageResetConfirm("suite_alpha") == false
    and suite.resets == resets and world.generic == nil, "combat did not refuse the provider page")
Check(Has(world, "print ") or Has(world, "combatlock"), "combat refusal must show the host's combat lock message")
world.combat = false
-- Inside an open history transaction the history wrapper runs nested work
-- without its own combat check, so the reset path must refuse by itself.
local nested
M.RunWithHistory("outer", "test:outer", function()
    world.combat = true
    nested = M.ResetPageToDefaults("suite_alpha")
    world.combat = false
    return false
end)
Check(nested == false and suite.resets == resets, "a nested provider reset ran in combat")

-- Confirmation: Blizzard's generic dialog, nothing written to StaticPopupDialogs.
Clear(world)
local writes = #world.popupWrites
Check(M.ShowPageResetConfirm("suite_alpha") == true, "the provider page did not ask")
Check(#world.popupWrites == writes and not Has(world, "InstallStaticPopup") and not Has(world, "StaticPopup_Show")
    and not Has(world, "ShowPrompt"),
    "the provider confirmation wrote StaticPopupDialogs or used the host's named dialog: " .. Logged(world))
Check(world.generic.text == "Suite warning suite_alpha" and world.generic.data.text == "%s",
    "the confirmation must show the provider's warning as a format argument")
local firstData = world.generic.data
world.generic.data.callback()
Check(suite.resets == resets + 1, "Yes did not reset the page")
-- A '%' in a warning is shown as is.
suite.text = "100% of"
Check(M.ShowPageResetConfirm("suite_beta") and world.generic.text == "100% of suite_beta", "a '%' broke the warning")
-- One question at a time: the next question replaces the visible one.
Check(world.generic.data == firstData and world.generic.replaced, "each question must reuse the one dialog data")
-- Yes in combat refuses; Yes resolves the page owner at that moment.
world.combat = true
world.generic.data.callback()
world.combat = false
Check(suite.resets == resets + 1, "a confirmation answered in combat reset the page")
local replacement = Provider(world, { suite_beta = true }, { text = "Replacement" })
M.RegisterPageResetProvider("msuf-suite", replacement)
world.generic.data.callback()
Check(replacement.resets == 1 and suite.resets == resets + 1, "Yes must reset through the page's current owner")
suite.text = "Suite warning"

-- Warnings: provider text, else the host's standard text.
replacement.text = nil
Check(M.BuildPageResetWarning("suite_beta"):find("^Reset Beta to defaults%?\n\nThis resets Beta for the active profile%.")
    ~= nil, "a nil provider warning must give the host's standard warning")
local hostBars = Boot().M.BuildPageResetWarning("opt_bars")
replacement.pages.opt_bars = true
M.RefreshPageResetProvider("msuf-suite")
Check(M.PageHasReset("opt_bars") == true and M.BuildPageResetWarning("opt_bars") == hostBars,
    "a nil warning on a host page must give that page's own host warning")
replacement.text = "Own"
Check(M.BuildPageResetWarning("opt_bars") == "Own opt_bars", "the provider's warning must win on a host page")

-- 4. Registration: replace, overlaps, refresh, validation.
Check(M.PageHasReset("suite_alpha") == false and M.PageResetProviders.suite_alpha == nil,
    "re-registering an id must replace its pages")
replacement.pages.suite_gamma = true
Check(M.PageResetProviders.suite_gamma == nil, "a pages change must wait for RefreshPageResetProvider")
toolbar = 0
Check(M.RefreshPageResetProvider("msuf-suite") == true and M.PageResetProviders.suite_gamma.source == replacement
    and toolbar == 1, "RefreshPageResetProvider must re-read the pages and refresh the toolbar")
Check(M.RefreshPageResetProvider("missing") == false, "refreshing an unknown id must report false")
local other = Provider(world, { suite_gamma = true }, { text = "Other" })
M.RegisterPageResetProvider("other", other)
Check(M.BuildPageResetWarning("suite_gamma") == "Other suite_gamma", "the latest registration must own an overlap")
other.pages.suite_gamma = nil
M.RefreshPageResetProvider("other")
Check(M.PageResetProviders.suite_gamma.source == replacement, "a dropped overlap must return to the earlier provider")
M.RegisterPageResetProvider("msuf-suite", replacement)
Check(M.PageResetProviders.suite_gamma.source == replacement, "re-registration must keep the provider's pages")
for _, bad in ipairs({ { nil, replacement }, { "", replacement }, { "x", nil }, { "x", { pages = {} } },
    { "x", { pages = 1, canReset = print, warning = print, reset = print } },
    { "x", { pages = {}, canReset = print, warning = print } } }) do
    local ok = pcall(M.RegisterPageResetProvider, bad[1], bad[2])
    Check(not ok, "an invalid registration was accepted: " .. Show(bad))
end
Check(M.PageResetProviders.suite_beta.source == replacement and M.PageResetProviders.x == nil,
    "an invalid registration changed the registry")
replacement.pages = "broken"
Check(not pcall(M.RefreshPageResetProvider, "msuf-suite"), "a provider without a pages table must raise on refresh")
replacement.pages = { suite_beta = true }
M.RefreshPageResetProvider("msuf-suite")

------------------------------------------------------------------------------
-- 5. An old Suite still wraps the four functions next to the empty registry.
local LEGACY_WRAP = [==[
local M, P, Suite, S, PAGE_MODULES, PageAddOnEnabled, YES, NO = ...
local function InstallPageResets()
    if M._msufSuitePageResetsInstalled then return end
    M._msufSuitePageResetsInstalled = true
    local oldHas, oldWarning = M.PageHasReset, M.BuildPageResetWarning
    local oldReset, oldConfirm = M.ResetPageToDefaults, M.ShowPageResetConfirm
    -- Second result: whether the page resets.
    local function IsSuitePage(key)
        for _, page in ipairs(P.pages) do if page.key == key then return true, page.reset ~= false and PageAddOnEnabled(key) end end
        return false
    end
    function M.PageHasReset(key)
        local suite, resettable = IsSuitePage(key)
        if suite then return resettable end
        return (oldHas and oldHas(key)) or false
    end
    -- The page's title in the reader's language (its key when it has none).
    local function PageTitle(key)
        for _, page in ipairs(P.pages) do
            if page.key == key then return P.Tr(page.title) end
        end
        return key
    end
    function M.BuildPageResetWarning(key)
        if not IsSuitePage(key) then return oldWarning and oldWarning(key) end
        return string.format(P.Tr("Reset %s to defaults?\n\nThis resets all settings on this Suite page for the active profile."),
            PageTitle(key))
    end
    function M.ResetPageToDefaults(key)
        local suite, resettable = IsSuitePage(key)
        if not suite then return oldReset and oldReset(key) or false end
        if not resettable or P.Combat() then return false end
        if key == "suite_skin" and not Suite.Skin.EnsureEngine() then return false end
        local ok = P.WithHistory(string.format(P.Tr("Reset %s"), PageTitle(key)), "page:reset:" .. tostring(key), function()
            if key == "suite_skin" then return P.ResetSkinPage() or false end
            local modules = PAGE_MODULES[key]
            if not modules then return false end
            for _, id in ipairs(modules) do if not S.Reset(id) then return false end end
            return true
        end)
        if ok then
            P.Refresh()
            if M.ShowStatusFeedback then M.ShowStatusFeedback(P.Tr("Page reset"), "ok", 1.5) end
        end
        return ok
    end
    function M.ShowPageResetConfirm(key)
        local suite, resettable = IsSuitePage(key)
        if not suite then return oldConfirm and oldConfirm(key) or false end
        if not resettable or P.Combat() then return false end
        local message = M.BuildPageResetWarning(key)
        if not M.InstallStaticPopup then
            return M.ResetPageToDefaults(key)
        end
        M.InstallStaticPopup("MSUF_SUITE_PAGE_RESET_CONFIRM", {
            text = "%s", button1 = YES, button2 = NO,
            OnAccept = function(_, data)
                if data and data.pageKey then M.ResetPageToDefaults(data.pageKey) end
            end,
        })
        StaticPopup_Show("MSUF_SUITE_PAGE_RESET_CONFIRM", message, nil, { pageKey = key })
        return true
    end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
end
InstallPageResets()
]==]
do
    local legacy = Boot()
    local reset = 0
    local P = {
        pages = { { key = "suite_old", title = "Old" } },
        Tr = function(text) return text end,
        Combat = function() return legacy.combat end,
        WithHistory = function(label, source, fn) return legacy.M.RunWithHistory(label, source, fn) end,
        Refresh = function() legacy.Log("suite:refresh") end,
    }
    local S = { Reset = function() reset = reset + 1 legacy.globals.MSUF_DB.general.marker = reset + 1 return true end }
    local chunk = assert(loadstring(LEGACY_WRAP, "=legacy-suite-register"))
    setfenv(chunk, legacy.env)(legacy.M, P, {}, S, { suite_old = { "module" } }, function() return true end, "Yes", "No")
    local LM = legacy.M
    Check(LM.PageHasReset ~= legacy.own[1] and next(LM.PageResetProviders) == nil,
        "the old Suite wrap must install over an empty registry")
    Check(LM.PageHasReset("suite_old") == true and LM.BuildPageResetWarning("suite_old"):find("Suite page", 1, true),
        "the old Suite wrap lost its pages")
    Clear(legacy)
    Check(LM.ResetPageToDefaults("suite_old") == true and reset == 1 and Has(legacy, "suite:refresh")
        and LM.historyUndo[#LM.historyUndo].label == "Reset Old", "the old Suite wrap did not reset through the host history")
    Check(LM.ShowPageResetConfirm("suite_old") == true and legacy.shown.which == "MSUF_SUITE_PAGE_RESET_CONFIRM",
        "the old Suite wrap did not ask")
    -- Host keys through the wrap behave as without it.
    local wrapped = {}
    local plain = Boot()
    for _, key in ipairs({ "uf_player", "opt_bars", "unknown" }) do
        wrapped[#wrapped + 1] = tostring(LM.PageHasReset(key)) .. tostring(LM.BuildPageResetWarning(key))
        wrapped[#wrapped + 1] = tostring(plain.M.PageHasReset(key)) .. tostring(plain.M.BuildPageResetWarning(key))
        Check(wrapped[#wrapped] == wrapped[#wrapped - 1], "the old Suite wrap changed host key " .. key)
    end
end

------------------------------------------------------------------------------
-- 6. The provider steps around the history entry (review CX-R9).
local function StepProvider(w, key, steps)
    local provider = {
        pages = { [key] = true },
        canReset = function() return true end,
        warning = function() return "Reset " .. key .. "?" end,
        reset = function() return true end,
    }
    for name, fn in pairs(steps or {}) do provider[name] = fn end
    w.M.RegisterPageResetProvider("msuf-suite", provider)
    return provider
end
local function Errors(w)
    local out = {}
    for _, line in ipairs(w.log) do if line:find("^error ") then out[#out + 1] = line end end
    return out
end
local function Entries(w) return #(w.M.historyUndo or {}) end

do
    -- prepare runs before the undo snapshot, so a dormant state it loads (the
    -- Suite's Skin profile) is what Undo restores; finish runs after the
    -- committed entry. One entry only.
    local w = Boot()
    local WM = w.M
    local skin, loaded, trace = { profile = 7 }, false, {}
    WM.RegisterHistoryProvider("suite-skin", function()
        return loaded and { profile = skin.profile } or nil
    end, function(state) skin.profile = state.profile end)
    local function Note(step) trace[#trace + 1] = step .. ":" .. tostring(WM.IsHistoryCapturing()) .. ":" .. Entries(w) end
    StepProvider(w, "suite_skin", {
        prepare = function() Note("prepare") loaded = true return true end,
        reset = function() Note("reset") skin.profile = 0 return true end,
        finish = function() Note("finish") w.Log("suite:refresh") end,
        historyLabel = function() return "Skinning zur\195\188cksetzen" end,
    })
    Check(WM.ResetPageToDefaults("suite_skin") == true, "the prepared provider reset failed")
    Check(table.concat(trace, " ") == "prepare:false:0 reset:true:0 finish:false:1",
        "prepare must run before the history, reset inside it, finish after the committed entry: " .. table.concat(trace, " "))
    Check(Entries(w) == 1 and WM.historyUndo[1].label == "Skinning zur\195\188cksetzen"
        and WM.historyUndo[1].source == "page:reset:suite_skin", "one entry under the provider's own label")
    Check(WM.Undo() and skin.profile == 7, "Undo did not restore the state prepare loaded: 7 -> 0 -> " .. tostring(skin.profile))
    -- prepare refusing (anything but true) stops the reset before the history.
    for _, answer in ipairs({ false, "yes" }) do
        local resets = 0
        StepProvider(w, "suite_skin", { prepare = function() return answer end,
            reset = function() resets = resets + 1 return true end })
        local before = Entries(w)
        Check(WM.ResetPageToDefaults("suite_skin") == false and resets == 0 and Entries(w) == before,
            "prepare answering " .. tostring(answer) .. " must refuse the reset")
    end
end

do
    -- The same inside an open menu session (the menu starts one when shown): the
    -- session snapshot from before prepare is the reset's "before" unless the
    -- host refreshes it. Shaped like the Suite's state: one history provider
    -- whose Skinning part is missing while that engine is dormant.
    local w = Boot()
    local WM = w.M
    local suiteRoot, skin, loaded = { setting = 1 }, { profile = 7 }, false
    WM.RegisterHistoryProvider("MSUF_Suite", function()
        return { root = { setting = suiteRoot.setting }, skin = loaded and { profile = skin.profile } or nil }
    end, function(state)
        suiteRoot.setting = state.root.setting
        if state.skin then skin.profile = state.skin.profile end
    end)
    Check(WM.StartHistorySession("menu") == true, "the menu session did not start")
    WM.RunWithHistory("Earlier change", "test:earlier", function()
        w.globals.MSUF_DB.general.marker = 5
        suiteRoot.setting = 2
        return true
    end)
    local before = Entries(w)
    StepProvider(w, "suite_skin", {
        prepare = function() loaded = true return true end,
        reset = function() skin.profile = 0 return true end,
    })
    Check(WM.ResetPageToDefaults("suite_skin") == true and Entries(w) == before + 1 and WM.IsHistoryCapturing() == false,
        "the session reset must add exactly one entry")
    Check(WM.Undo() and skin.profile == 7 and w.globals.MSUF_DB.general.marker == 5 and suiteRoot.setting == 2,
        "Undo in an open session did not restore what prepare loaded: 7 -> 0 -> " .. tostring(skin.profile))
    Check(WM.Redo() and skin.profile == 0, "Redo did not reapply the session reset")
    -- Discarding the session still discards it: the earlier change goes, and
    -- the undo stack is back to where the session started.
    Check(WM.CancelHistorySurface("menu", true) == true and w.globals.MSUF_DB.general.marker == 1
        and suiteRoot.setting == 1 and Entries(w) == 0, "discarding the session no longer discards it")
    WM.EndHistorySession("menu")
end

do
    -- The undo label: the provider's own, else the host's translated "Reset %s"
    -- with the translated page title.
    local w = Boot()
    local WM = w.M
    local TR = { ["Reset %s"] = "%s zur\195\188ckgesetzt", Alpha = "Alpha-DE" }
    WM.Tr = function(text) return TR[text] or text end
    for _, label in ipairs({ false, "" }) do
        StepProvider(w, "suite_alpha", { historyLabel = function() return label or nil end,
            reset = function() w.globals.MSUF_DB.general.marker = w.globals.MSUF_DB.general.marker + 1 return true end })
        Check(WM.ResetPageToDefaults("suite_alpha") == true, "the labelled reset failed")
        Check(WM.historyUndo[#WM.historyUndo].label == "Alpha-DE zur\195\188ckgesetzt",
            "the fallback label must be the translated host phrase: " .. tostring(WM.historyUndo[#WM.historyUndo].label))
    end
end

do
    -- A raising step is reported through the boundary; the history closes, a
    -- partial reset stays undoable, and later changes still make entries.
    local function Later(w)
        local before = Entries(w)
        w.M.RunWithHistory("Later change", "test:later", function()
            w.globals.MSUF_DB.general.later = (w.globals.MSUF_DB.general.later or 0) + 1
            return true
        end)
        return Entries(w) == before + 1
    end
    local w = Boot()
    local WM = w.M
    StepProvider(w, "suite_alpha", { reset = function()
        w.globals.MSUF_DB.general.marker = 99
        error("injected reset failure")
    end })
    Check(WM.ResetPageToDefaults("suite_alpha") == false, "a raising reset must report false")
    local errors = Errors(w)
    Check(#errors == 1 and errors[1]:find("page-reset provider reset suite_alpha", 1, true)
        and errors[1]:find("injected reset failure", 1, true), "the reset error was not reported: " .. Logged(w))
    Check(WM.IsHistoryCapturing() == false, "a raising reset left the history capturing")
    Check(Entries(w) == 1 and WM.Undo() and w.globals.MSUF_DB.general.marker == 1,
        "the partial reset must stay undoable")
    Check(Later(w), "the history took no entry after a raising reset")

    w = Boot()
    WM = w.M
    local resets = 0
    StepProvider(w, "suite_alpha", { prepare = function() error("injected prepare failure") end,
        reset = function() resets = resets + 1 return true end })
    Check(WM.ResetPageToDefaults("suite_alpha") == false and resets == 0 and Entries(w) == 0,
        "a raising prepare must stop the reset before the history")
    Check(#Errors(w) == 1 and Errors(w)[1]:find("page-reset provider prepare suite_alpha", 1, true),
        "the prepare error was not reported")
    Check(WM.IsHistoryCapturing() == false and Later(w), "a raising prepare broke the history")

    w = Boot()
    WM = w.M
    StepProvider(w, "suite_alpha", {
        reset = function() w.globals.MSUF_DB.general.marker = 2 return true end,
        finish = function() error("injected refresh failure") end,
    })
    Check(WM.ResetPageToDefaults("suite_alpha") == true, "a raising finish must not undo the committed reset")
    Check(#Errors(w) == 1 and Errors(w)[1]:find("page-reset provider finish suite_alpha", 1, true),
        "the finish error was not reported")
    Check(Entries(w) == 1 and WM.IsHistoryCapturing() == false and Later(w), "a raising finish broke the history")
end

do
    -- PLAYER_REGEN_DISABLED: the lockdown has not started, the player is in
    -- combat. Reset, confirmation and a pending Yes all refuse.
    local w = Boot()
    local WM = w.M
    local steps = 0
    StepProvider(w, "suite_alpha", {
        prepare = function() steps = steps + 1 return true end,
        reset = function() steps = steps + 1 return true end,
    })
    Check(WM.ShowPageResetConfirm("suite_alpha") == true, "the confirmation did not open out of combat")
    local yes = w.generic.data.callback
    w.generic = nil
    w.regenEdge = true
    Clear(w)
    Check(WM.ResetPageToDefaults("suite_alpha") == false and WM.ShowPageResetConfirm("suite_alpha") == false
        and w.generic == nil, "the PLAYER_REGEN_DISABLED dispatch did not refuse the provider page")
    yes()
    Check(steps == 0 and Entries(w) == 0, "a step ran during the PLAYER_REGEN_DISABLED dispatch")
    Check(Has(w, "combatlock") or Has(w, "print "), "the edge refusal must show the host's combat message")
    w.regenEdge = false
    Check(WM.ResetPageToDefaults("suite_alpha") == true and steps == 2, "the reset did not run after the edge")
end

do
    -- A malformed provider never disturbs the others: every registration and
    -- refresh is checked before the page map changes.
    local w = Boot()
    local WM = w.M
    local function Owner(key) return WM.PageResetProviders[key] and WM.PageResetProviders[key].source end
    local a = { pages = { a1 = true }, canReset = function() return true end,
        warning = function() return "A" end, reset = function() return true end }
    local b = { pages = { b1 = true }, canReset = function() return true end,
        warning = function() return "B" end, reset = function() return true end }
    WM.RegisterPageResetProvider("a", a)
    WM.RegisterPageResetProvider("b", b)
    a.pages = nil
    Check(WM.RefreshPageResetProvider("b") == true and Owner("a1") == a and Owner("b1") == b,
        "refreshing one provider must not depend on another's pages")
    Check(not pcall(WM.RefreshPageResetProvider, "a"), "refreshing a provider without pages must raise")
    Check(Owner("a1") == a and Owner("b1") == b and WM.PageHasReset("a1") and WM.PageHasReset("b1"),
        "a failed refresh changed the page map")
    for _, bad in ipairs({ { pages = {}, canReset = print, warning = print, reset = print, prepare = 5 },
        { pages = {}, canReset = print, warning = print, reset = print, finish = "x" },
        { pages = {}, canReset = print, warning = print, reset = print, historyLabel = {} },
        { pages = { a1 = true }, warning = print, reset = print } }) do
        Check(not pcall(WM.RegisterPageResetProvider, "c", bad), "a malformed provider was accepted: " .. Show(bad))
        Check(not pcall(WM.RegisterPageResetProvider, "a", bad), "a malformed replacement was accepted: " .. Show(bad))
        Check(Owner("a1") == a and Owner("b1") == b, "a malformed registration changed the page map")
    end
    -- The checked copy keeps the callbacks the provider registered with.
    b.canReset = nil
    Check(WM.PageHasReset("b1") == true, "the registry must keep the callbacks it checked")
    a.pages = { a2 = true }
    Check(WM.RefreshPageResetProvider("a") and Owner("a2") == a and Owner("a1") == nil, "a fixed provider did not refresh")
end

------------------------------------------------------------------------------
-- 7. O(1) lookup, 0 KB per call.
do
    local perf = Boot()
    local pages = { target = true }
    local fast = { pages = pages, canReset = function() return true end,
        warning = function() return "Constant" end, reset = function() return true end }
    perf.M.RegisterPageResetProvider("performance", fast)
    local PM = perf.M
    local function Cost()
        local instructions = 0
        debug.sethook(function() instructions = instructions + 1 end, "", 1)
        for _ = 1, 100 do
            PM.PageHasReset("target")
            PM.BuildPageResetWarning("target")
            PM.PageHasReset("uf_player")
        end
        debug.sethook()
        return instructions
    end
    local small = Cost()
    for index = 1, 2000 do pages["unrelated" .. index] = true end
    PM.RefreshPageResetProvider("performance")
    for index = 1, 50 do
        PM.RegisterPageResetProvider("other" .. index, { pages = { ["more" .. index] = true },
            canReset = fast.canReset, warning = fast.warning, reset = fast.reset })
    end
    local large = Cost()
    Check(small == large, ("the provider lookup grows with the registry: %d -> %d VM instructions"):format(small, large))
    for _ = 1, 10 do PM.PageHasReset("target") PM.BuildPageResetWarning("target") PM.PageHasReset("uf_player") end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10000 do
        PM.PageHasReset("target")
        PM.BuildPageResetWarning("target")
        PM.PageHasReset("uf_player")
        PM.PageHasReset("unknown")
    end
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    Check(allocated == 0, ("the provider lookup allocated %.3f KB in 10000 calls"):format(allocated))
    print(("host_page_reset_provider_smoke: PASS (4 functions, unowned keys unchanged, combat, history, "
        .. "generic dialog, re-registration, old Suite wrap, prepare/finish/label, open-session undo, contained steps, REGEN edge, "
        .. "malformed providers; lookup %d VM instructions per 300 calls at 1 and 2051 pages, 0 KB)")
        :format(small))
end
