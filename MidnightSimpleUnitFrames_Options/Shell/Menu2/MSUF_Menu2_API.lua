--- Menu2 public globals, slash routing, and combat-hide bridge.
--- This file is the compatibility facade for older slash/global entry points. Keep it thin:
--- open/toggle/select calls delegate to Menu2, and combat entry hides the menu safely.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local M = MSUF.MSUF2 or _G.MSUF2
if not M then return end
local MenuRuntime = M.MenuRuntime or {}

-- M.Format is installed by MSUF_Menu2_Theme.lua. This file is also loaded by
-- audits and by Assistant entry points that run before the theme exists, so
-- route through a fallback instead of indexing a nil.
local function Fmt(text, ...)
    if type(M.Format) == "function" then return M.Format(text, ...) end
    local translated = type(M.Tr) == "function" and M.Tr(text) or text
    if select("#", ...) == 0 then return translated end
    return string.format(translated, ...)
end

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF2_Open", function(pageKey) M.Open(pageKey) end)
ExportPublic("MSUF2_Toggle", function(pageKey) M.Toggle(pageKey) end)
ExportPublic("MSUF_OpenStandaloneOptionsWindow", function(pageKey) M.Open(pageKey) end)
ExportPublic("MSUF_ShowStandaloneOptionsWindow", function(pageKey) M.Open(pageKey) end)
ExportPublic("MSUF_HideStandaloneOptionsWindow", function() M.CallIf(M.HideSlashMenuAndMinibar, M.frame) end)
ExportPublic("MSUF_OpenOptionsMenu", function() M.Open() end)
ExportPublic("MSUF_OpenPage", function(pageKey) return M.SelectPage(pageKey or "home") end)
ExportPublic("MSUF_SwitchMirrorPage", function(pageKey) return M.SelectPage(pageKey or "home") end)
ExportPublic("MSUF_GetCurrentMirrorPage", function() return M.activeKey or "home" end)
ExportPublic("MSUF_GetMirrorPages", function() return M.pages end)

local function VisibleControlDirection(page, label)
    local route = type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(page) or tostring(page or "MSUF menu")
    label = tostring(label or "")
    if label ~= "" and not tostring(route):find(label, 1, true) then return tostring(route) .. " > " .. label end
    return tostring(route)
end

local function OpenExactSettingControl(settingKey, fallbackLabel, fallbackPage)
    settingKey = tostring(settingKey or "")
    fallbackPage = tostring(fallbackPage or "")
    if settingKey == "" then return false, "Which exact MSUF option do you want me to open?" end
    if M.BlockCombatAction and M.BlockCombatAction() then
        return false, "I cannot open and focus an options control during combat. Try again after combat."
    end

    local bridge = M.SearchBridge
    local route
    local exactTarget = { settingKey = settingKey, pageKey = fallbackPage }
    -- Selector-dependent pages must receive their finite workspace route before
    -- M.Open lazily builds the page and before the runtime catalog is queried.
    if fallbackPage ~= "" and bridge and type(bridge.PrepareSearchTarget) == "function" then
        local _, preparedRoute, preparedTarget = bridge.PrepareSearchTarget(
            fallbackPage, fallbackLabel or settingKey, fallbackLabel, exactTarget)
        route = preparedRoute
        if type(preparedTarget) == "table" then exactTarget = preparedTarget end
    end

    local catalog = M.RuntimeControlCatalog
    local function FindControl(page)
        if catalog and type(catalog.FindBySettingKey) == "function" then
            return catalog.FindBySettingKey(settingKey, page)
        end
    end
    local record, widget = FindControl(fallbackPage)
    local page = tostring((record and record.pageKey) or fallbackPage or "")
    if page == "" then return false, "I know that setting, but its MSUF menu page is not mapped yet." end

    -- Opening the owning page lazily builds its real widgets and populates the
    -- runtime catalog. Resolve once more afterwards to obtain the exact anchor.
    if M.Open(page) == false then return false, "I could not open the MSUF options page." end
    local builtRecord, builtWidget = FindControl(page)
    record, widget = builtRecord or record, builtWidget or widget
    page = tostring((record and record.pageKey) or page)
    local label = tostring((record and (record.label or record.identityLabel)) or fallbackLabel or settingKey)
    local query = tostring((record and (record.identityLabel or record.label)) or fallbackLabel or settingKey)
    if bridge and type(bridge.OpenSearchTarget) == "function" then
        local called, opened, focused, exact = bridge.OpenSearchTarget(
            page, query, label, widget, route, exactTarget)
        if called and opened == false then
            return false, Fmt("I could not open the MSUF options page for %s.", label)
        end
        if called and focused == false then
            return false, Fmt("I opened %s, but its exact %s control is not available there anymore.",
                tostring(type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(page) or page), label)
        end
        if called and exact == false then
            return true, Fmt("Opened %s and highlighted the closest matching control.", VisibleControlDirection(page, label))
        end
    elseif type(M.SelectPage) == "function" then
        M.SelectPage(page)
    end
    return true, Fmt("Opened %s and focused its exact control.", VisibleControlDirection(page, label))
end

M.OpenExactSettingControl = OpenExactSettingControl
ExportPublic("MSUF_OpenExactSettingControl", OpenExactSettingControl)

-- Assistant-facing bridge for color settings. Reuse the real Menu2 color
-- button so the Color Painter gets the same live setter, history transaction,
-- context label, and cancellation behavior as a direct user click.
local function OpenExactColorSettingPicker(settingKey, fallbackLabel, fallbackPage)
    local opened, message = OpenExactSettingControl(settingKey, fallbackLabel, fallbackPage)
    if opened == false then return false, message end

    local catalog = M.RuntimeControlCatalog
    if not (catalog and type(catalog.FindBySettingKey) == "function") then
        return false, "I opened the setting, but the exact color control is not available yet."
    end
    local record, widget = catalog.FindBySettingKey(settingKey, fallbackPage)
    if not (record and widget and tostring(record.kind or "") == "color"
        and type(widget.GetRGB) == "function" and type(widget.SetRGB) == "function")
    then
        return false, "I opened the setting, but it is not exposed as a Color Painter control."
    end

    local openPicker = M.OpenColorContextPicker
        or (M.Widgets and M.Widgets.OpenColorContextPicker)
    if type(openPicker) ~= "function" then
        return false, "I opened the color setting, but Color Painter is not available yet."
    end

    local label = tostring(record.label or record.identityLabel or fallbackLabel or settingKey)
    local owners = type(widget._msuf2ColorContextOwners) == "table"
        and widget._msuf2ColorContextOwners or { widget }
    openPicker(widget._msuf2ColorContextTitle or label, owners,
        widget._msuf2ColorContextNote or "Opened from the MSUF Assistant.", widget)
    return true, Fmt("Opened Color Painter for %s.", label)
end

M.OpenExactColorSettingPicker = OpenExactColorSettingPicker
ExportPublic("MSUF_OpenExactColorSettingPicker", OpenExactColorSettingPicker)

local function OpenExactCatalogControl(semanticId, fallbackLabel, fallbackPage)
    semanticId = tostring(semanticId or "")
    fallbackPage = tostring(fallbackPage or "")
    if semanticId == "" then return false, "Which exact MSUF control do you want me to open?" end
    if M.BlockCombatAction and M.BlockCombatAction() then
        return false, "I cannot open and focus an options control during combat. Try again after combat."
    end

    local catalog = M.RuntimeControlCatalog
    if not (catalog and type(catalog.Resolve) == "function") then
        return false, "The exact-control catalog is not available yet. Reopen the MSUF menu and try again."
    end
    if fallbackPage == "" then return false, "I know that control, but its MSUF menu page is not mapped yet." end

    local bridge = M.SearchBridge
    local route
    local exactTarget = { semanticId = semanticId, pageKey = fallbackPage }
    -- Generated rows can live behind an Aura lane/tool selector and therefore
    -- do not exist in the current runtime catalog until that route is applied.
    if bridge and type(bridge.PrepareSearchTarget) == "function" then
        local _, preparedRoute, preparedTarget = bridge.PrepareSearchTarget(
            fallbackPage, fallbackLabel or semanticId, fallbackLabel, exactTarget)
        route = preparedRoute
        if type(preparedTarget) == "table" then exactTarget = preparedTarget end
    end
    if M.Open(fallbackPage) == false then return false, "I could not open the MSUF options page." end

    local record, widget = catalog.Resolve(semanticId, { pageKey = fallbackPage })
    if not record then
        return false, Fmt("I opened %s, but that exact control is not available in the current context.", fallbackPage)
    end
    local page = tostring(record.pageKey or fallbackPage)
    local label = tostring(record.label or record.identityLabel or fallbackLabel or semanticId)
    local query = tostring(record.identityLabel or record.label or fallbackLabel or semanticId)
    if bridge and type(bridge.OpenSearchTarget) == "function" then
        local called, opened, focused = bridge.OpenSearchTarget(
            page, query, label, widget, route, exactTarget)
        if called and opened == false then
            return false, Fmt("I could not open the MSUF options page for %s.", label)
        end
        if called and focused == false then
            return false, Fmt("I opened %s, but its exact %s control is not available there anymore.",
                tostring(type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(page) or page), label)
        end
    elseif type(M.SelectPage) == "function" then
        M.SelectPage(page)
    end
    return true, Fmt("Opened %s and focused its exact control.", VisibleControlDirection(page, label))
end

M.OpenExactCatalogControl = OpenExactCatalogControl
ExportPublic("MSUF_OpenExactCatalogControl", OpenExactCatalogControl)
do
    local combatFrame
    local combatRegistered = false

    -- Options UI is not useful once protected combat starts and may try to focus protected
    -- edit surfaces. Register the listener only while the window/minibar is visible.
    local function MenuVisible()
        local win = M.frame
        local bar = M.minimizedBar
        local barShown = bar and bar.IsShown and bar:IsShown()
        if barShown then return true end
        local winShown = win and win.IsShown and win:IsShown()
        -- The full window's status frame already owns PLAYER_REGEN_DISABLED.
        -- Keep this fallback listener only for the minimized bar (or an early
        -- window lifecycle without its status events) so combat entry never
        -- dispatches duplicate Menu2 teardown callbacks.
        local status = win and win.status
        if winShown and status and status._msuf2EventsRegistered == true then return false end
        return winShown and true or false
    end
    local function EnsureCombatFrame()
        if combatFrame then return end
        combatFrame = CreateFrame("Frame")
        combatFrame:SetScript("OnEvent", function()
            if not MenuVisible() then
                M.UpdateMenuCombatListener()
                return
            end
            local win = M.frame
            local winShown = win and win.IsShown and win:IsShown()
            -- A visible full window quiesces from its synchronous OnHide.
            -- The fallback owns teardown only when the minimized bar is the
            -- remaining visible Menu2 surface.
            if not winShown and type(MenuRuntime.Quiesce) == "function" then MenuRuntime:Quiesce("combat") end
            M.CallIf(M.BlockCombatAction)
            M.CallIf(M.HideSlashMenuAndMinibar, win)
            M.UpdateMenuCombatListener()
        end)
    end
    function M.UpdateMenuCombatListener()
        if MenuVisible() then
            EnsureCombatFrame()
            if combatFrame and not combatRegistered then
                combatRegistered = true
                combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            end
        elseif combatFrame and combatRegistered then
            combatRegistered = false
            combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
    end
end
--- ==========================================================================
--- Menu-owned slash commands
---
--- The registry itself lives in Runtime/MSUF_SlashCommands.lua, which loads
--- long before Menu2. Everything registered here needs the menu window, the
--- search index or MSUF Edit Mode, so it cannot live in the runtime file.
--- Registration is load-time table work only: no events, no hooks, no timers.
--- ==========================================================================
local Commands = MSUF.SlashCommands

--- `/msuf edit target` should land on the target frame. The menu already owns
--- the "word the player typed -> page" mapping, so reuse it and strip the page
--- prefix instead of maintaining a second unit-name table that can drift.
local function SlashEditUnitKey(rest)
    rest = tostring(rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if rest == "" then return nil end
    local aliases = M.ALIASES or {}
    local pageKey = aliases[rest] or rest
    if pageKey == "gf_priority" then return "gf_priority" end
    return pageKey:match("^uf_(.+)$")
end

local function SlashOpenSearch(query)
    query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return M.Open("search") end
    --- The window must exist before the search page can be selected. M.Open
    --- returns false when combat blocks the menu, which ends the command here.
    if not M.Open("search") then return false end
    local bridge = M.SearchBridge
    if not (bridge and type(bridge.RunSearchQuery) == "function") then return false end
    local ok, err = bridge.RunSearchQuery(query)
    if not ok and err then print("|cffff0000MSUF:|r " .. tostring(err)) end
    return ok
end

local function RegisterMenuCommand(entry)
    if type(Commands) ~= "table" or type(Commands.Register) ~= "function" then return false end
    local existing = type(Commands.Get) == "function" and Commands.Get(entry and entry.name) or nil
    if type(existing) ~= "table" or existing._msufOptionsLODDeferred ~= true then
        return Commands.Register(entry)
    end

    --- Replace the cold metadata entry in place so Commands.order keeps the
    --- exact eager-load ordering and every alias starts calling the real
    --- implementation immediately after the Options addon finishes loading.
    local byWord = Commands.byWord
    if type(byWord) ~= "table" then return false end
    local function Words(value)
        local words = { tostring(value.name or ""):lower() }
        for i = 1, #(value.aliases or {}) do
            words[#words + 1] = tostring(value.aliases[i]):lower()
        end
        return words
    end
    local oldWords, newWords = Words(existing), Words(entry)
    for i = 1, #newWords do
        local owner = byWord[newWords[i]]
        if owner ~= nil and owner ~= existing then return false end
    end
    for i = 1, #oldWords do
        if byWord[oldWords[i]] == existing then byWord[oldWords[i]] = nil end
    end
    for key in pairs(existing) do existing[key] = nil end
    for key, value in pairs(entry) do existing[key] = value end
    existing.name = tostring(existing.name or ""):lower()
    for i = 1, #newWords do byWord[newWords[i]] = existing end
    return true
end

if type(Commands) == "table" and type(Commands.Register) == "function" then
RegisterMenuCommand({
    name = "edit",
    aliases = { "editmode", "move", "unlock" },
    group = "frames",
    usage = "/msuf edit [unit]",
    help = "Toggle MSUF Edit Mode. Add a unit such as player or target to open it there.",
    run = function(rest)
        local unitKey = SlashEditUnitKey(rest)
        if rest ~= "" and not unitKey then
            print(string.format(M.Tr("|cffff0000MSUF:|r Unknown frame '%s'. Try player, target, focus, pet, boss or priority."), rest))
            return
        end
        if type(M.EditModeLifecycleStatus) ~= "function" then return end
        local status = M.EditModeLifecycleStatus()
        --- Edit Mode is already running: re-entering with a unit retargets it
        --- rather than toggling the whole mode off under the player.
        if unitKey and status.active then
            local setFn = rawget(_G, "MSUF_SetMSUFEditModeDirect")
            if type(setFn) == "function" then setFn(true, unitKey) end
            return
        end
        if unitKey then return M.SetMSUFEditModeActive(true, unitKey, { source = "slash" }) end
        return M.ToggleMSUFEditMode(nil, { source = "slash" })
    end,
})

RegisterMenuCommand({
    name = "lock",
    aliases = { "unedit" },
    group = "frames",
    usage = "/msuf lock",
    help = "Leave MSUF Edit Mode.",
    run = function()
        if type(M.EditModeLifecycleStatus) ~= "function" then return end
        if not M.EditModeLifecycleStatus().active then
            print(M.Tr("|cffffd700MSUF:|r MSUF Edit Mode is not running."))
            return
        end
        return M.SetMSUFEditModeActive(false, nil, { source = "slash" })
    end,
})

RegisterMenuCommand({
    name = "search",
    aliases = { "find" },
    group = "general",
    usage = "/msuf search <text>",
    help = "Search the options menu and open the matching settings.",
    run = function(rest)
        return SlashOpenSearch(rest)
    end,
})

RegisterMenuCommand({
    name = "tour",
    aliases = { "guide", "setup" },
    group = "general",
    usage = "/msuf tour",
    help = "Start or resume the guided setup.",
    run = function()
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        local tour = MSUF and MSUF.GuidedTour6
        local active = type(tour) == "table" and type(tour.IsActive) == "function" and tour:IsActive()
        if active and type(M.ResumeGuidedTour) == "function" then
            M.ResumeGuidedTour()
        elseif type(M.StartGuidedTour) == "function" then
            M.StartGuidedTour({ source = "slash" })
        else
            M.Open("home")
        end
    end,
})

RegisterMenuCommand({
    name = "locale",
    aliases = { "locales", "loc" },
    group = "diagnostics",
    dev = true,
    usage = "/msuf locale",
    help = "Report how much of the current language is translated.",
    run = function()
        local total, missing = 0, 0
        if type(M.GetLocaleCoverage) == "function" then total, missing = M.GetLocaleCoverage() end
        local locale = MSUF.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
        print(string.format("|cff00b7ebMSUF2|r locale %s: %d keys seen, %d missing translations.", locale, total or 0, missing or 0))
    end,
})

RegisterMenuCommand({
    name = "versiontest",
    group = "diagnostics",
    dev = true,
    usage = "/msuf versiontest",
    help = "Fake an available update to test the version-check popup.",
    run = function()
        if type(_G.MSUF_VersionCheck_DebugFakeUpdate) == "function" then
            _G.MSUF_VersionCheck_DebugFakeUpdate()
        else
            print("|cffffd700MSUF:|r Version test helper is not loaded.")
        end
    end,
})

RegisterMenuCommand({
    name = "firstload",
    group = "diagnostics",
    dev = true,
    usage = "/msuf firstload [fresh/upgrade/status]",
    help = "Replay the first-start flow or the upgrade highlights.",
    run = function(rest)
        local msg = rest:lower()
        local firstLoad = MSUF and MSUF.FirstLoad6
        if type(firstLoad) ~= "table" or type(firstLoad.Reset) ~= "function" then
            print("|cff00b7ebMSUF|r: First-load module is not loaded.")
            return
        end
        local arg = msg:match("^(%S+)") or ""
        if arg == "status" then
            local shows = type(firstLoad.ShouldShowDashboard) == "function" and firstLoad:ShouldShowDashboard()
            local state = type(firstLoad.GetState) == "function" and firstLoad:GetState() or {}
            local detection = type(firstLoad.GetDetection) == "function" and firstLoad:GetDetection() or {}
            print(string.format("|cff00b7ebMSUF|r first-load: status=%s step=%s install=%s shows=%s reason=%s profile=%s legacy=%s schema=%s rawDB=%s rawProfiles=%s",
                tostring(state.status), tostring(state.step), tostring(state.installKind),
                tostring(shows), tostring(detection.reason), tostring(detection.existingProfile),
                tostring(detection.legacyProfile), tostring(detection.profileSchema or "none"),
                tostring(detection.rawDB), tostring(detection.rawProfiles)))
            local highlights = MSUF and MSUF.UpgradeHighlights
            if type(highlights) == "table" and type(highlights.GetDebugSummary) == "function" then
                local releaseKey, status, index, count = highlights:GetDebugSummary()
                print(string.format("|cff00b7ebMSUF|r upgrade-highlights: release=%s status=%s index=%s count=%s shows=%s",
                    tostring(releaseKey), tostring(status), tostring(index), tostring(count),
                    tostring(type(highlights.ShouldShow) == "function" and highlights:ShouldShow() or false)))
            end
            return
        end
        if arg ~= "" and arg ~= "fresh" and arg ~= "upgrade" then
            print("|cff00b7ebMSUF|r: Usage: /msuf firstload [fresh|upgrade|status]")
            return
        end
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        -- A clean preview also needs the guided tour parked, otherwise an
        -- active tour would take over the next menu open.
        local tour = MSUF and MSUF.GuidedTour6
        if type(tour) == "table" and type(tour.Reset) == "function" then tour:Reset() end
        firstLoad:Reset(arg ~= "" and arg or nil)
        local highlights = MSUF and MSUF.UpgradeHighlights
        if type(highlights) == "table" then
            if firstLoad:GetInstallKind() == "fresh" and type(highlights.BaselineKnownReleases) == "function" then
                highlights:BaselineKnownReleases()
            elseif type(highlights.ResetCurrent) == "function" then
                highlights:ResetCurrent()
            end
        end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
        M.Open("home")
        print(Fmt("|cff00b7ebMSUF|r: First-start preview re-armed (%s). Guided-tour progress was reset.", tostring(firstLoad:GetInstallKind())))
    end,
})

--- Anything that is not a registered command is a page name, and anything that
--- is not a page name is a search. The old handler opened an empty "native page
--- missing" placeholder for every typo, which is what made /msuf edit look
--- broken before Edit Mode had a command of its own.
Commands.SetFallback(function(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then return M.Open() end
    local aliases = M.ALIASES or {}
    local word = msg:lower()
    local pageKey = aliases[word] or word
    if type(M.pages) == "table" and M.pages[pageKey] then return M.Open(pageKey) end
    return SlashOpenSearch(msg)
end)
end

SLASH_MSUF2OPTIONS1 = "/msuf"
SlashCmdList["MSUF2OPTIONS"] = function(msg)
    if type(Commands) == "table" and type(Commands.Dispatch) == "function" then
        return Commands.Dispatch(msg)
    end
    local aliases = M.ALIASES or {}
    msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    M.Open(msg ~= "" and (aliases[msg] or msg) or nil)
end
SLASH_MSUFOPTIONS1 = SLASH_MSUFOPTIONS1 or "/msufoptions"
local optionsSlashHandler = function(msg)
    if type(Commands) == "table" and type(Commands.Dispatch) == "function" then
        return Commands.Dispatch(msg)
    end
    local aliases = M.ALIASES or {}
    msg = tostring(msg or ""):lower()
    local pageKey = msg ~= "" and (aliases[msg] or msg) or nil
    M.Open(pageKey)
end
if not SlashCmdList["MSUFOPTIONS"]
    or SlashCmdList["MSUFOPTIONS"] == MSUF.OptionsLODMSUFOptionsStub
then
    SlashCmdList["MSUFOPTIONS"] = optionsSlashHandler
end
MSUF.OptionsLODMSUFOptionsStub = nil

-- Stable integration points for Edit Mode and external launchers. Resolve the
-- controller at click time because it is loaded after all Menu2 pages.
ExportPublic("MSUF_StartGuidedTour", function(opts)
    return type(M.StartGuidedTour) == "function" and M.StartGuidedTour(opts)
end)
ExportPublic("MSUF_ResumeGuidedTour", function()
    return type(M.ResumeGuidedTour) == "function" and M.ResumeGuidedTour()
end)
