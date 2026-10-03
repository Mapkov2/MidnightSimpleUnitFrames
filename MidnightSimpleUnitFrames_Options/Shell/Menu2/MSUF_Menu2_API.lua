--- Menu2 public globals, slash routing, and combat-hide bridge.
--- This file is the compatibility facade for older slash/global entry points. Keep it thin:
--- open/toggle/select calls delegate to Menu2, and combat entry hides the menu safely.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local M = MSUF.MSUF2 or _G.MSUF2
if not M then return end
local MenuRuntime = M.MenuRuntime or {}

-- M.Format is installed by MSUF_Menu2_Theme.lua, which MSUF_Menu2.xml loads
-- before this file.
local Fmt = M.Format

local ExportPublic = MSUF.ExportPublic

ExportPublic("MSUF2_Open", function(pageKey) M.Open(pageKey) end)
ExportPublic("MSUF2_Toggle", function(pageKey) M.Toggle(pageKey) end)
ExportPublic("MSUF_OpenStandaloneOptionsWindow", function(pageKey) M.Open(pageKey) end)
ExportPublic("MSUF_ShowStandaloneOptionsWindow", function(pageKey) M.Open(pageKey) end)
ExportPublic("MSUF_HideStandaloneOptionsWindow", function() M.HideSlashMenuAndMinibar(M.frame) end)
ExportPublic("MSUF_OpenOptionsMenu", function() M.Open() end)
ExportPublic("MSUF_OpenPage", function(pageKey) return M.SelectPage(pageKey or "home") end)
ExportPublic("MSUF_SwitchMirrorPage", function(pageKey) return M.SelectPage(pageKey or "home") end)
ExportPublic("MSUF_GetCurrentMirrorPage", function() return M.activeKey or "home" end)
ExportPublic("MSUF_GetMirrorPages", function() return M.pages end)

-- The missing cooldown-anchor warning opens its real setting through this
-- public navigation entry point. It never invokes the setting's action.
local function OpenExactSettingControl(settingKey, label, pageKey)
    if type(settingKey) ~= "string" or settingKey == ""
        or type(pageKey) ~= "string" or not M.pages[pageKey] then return false end
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    local bridge = M.SearchBridge
    if not (bridge and type(bridge.OpenSearchTarget) == "function") then return false end
    -- The route is applied and the target page built once, by OpenSearchTarget.
    -- A shown window needs no open; a hidden one reopens on its cached page.
    if not (M.frame and M.frame.IsShown and M.frame:IsShown())
        and M.Open(M.activeKey or pageKey) == false then return false end
    local exactTarget = { pageKey = pageKey, settingKey = settingKey }
    local static = M.Search and M.Search.StaticIndex
    if static and type(static.GetRecords) == "function" then
        for _, record in ipairs(static.GetRecords()) do
            local target = record.exactTarget
            if record.key == pageKey and target and target.settingKey == settingKey then
                exactTarget = target
                break
            end
        end
    end
    local route
    if type(bridge.RouteForExactTarget) == "function" then
        route = bridge.RouteForExactTarget(pageKey, label or settingKey, label, exactTarget)
    end
    if exactTarget.sectionId then
        route = route or {}
        route.accordion = route.accordion or {}
        route.accordion[pageKey .. ":" .. exactTarget.sectionId] = true
    end
    local called, opened, focused, exact = bridge.OpenSearchTarget(
        pageKey, label or settingKey, label, nil, route, exactTarget)
    return called and opened and focused and exact == true
end
M.OpenExactSettingControl = OpenExactSettingControl
ExportPublic("MSUF_OpenExactSettingControl", OpenExactSettingControl)

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
        combatFrame:SetScript("OnEvent", function(_, event)
            if not MenuVisible() then
                M.UpdateMenuCombatListener()
                return
            end
            local win = M.frame
            local winShown = win and win.IsShown and win:IsShown()
            -- A visible full window quiesces from its synchronous OnHide.
            -- The fallback owns teardown only when the minimized bar is the
            -- remaining visible Menu2 surface. The event goes along: the
            -- lockdown starts only after PLAYER_REGEN_DISABLED.
            if not winShown and type(MenuRuntime.Quiesce) == "function" then MenuRuntime:Quiesce("combat", event) end
            M.BlockCombatAction(event)
            M.HideSlashMenuAndMinibar(win)
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
        total, missing = M.GetLocaleCoverage()
        local locale = MSUF.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
        print("|cff00b7ebMSUF|r " .. Fmt("Locale %s: %d keys seen, %d missing translations.", locale, total or 0, missing or 0))
    end,
})

RegisterMenuCommand({
    name = "versiontest",
    group = "diagnostics",
    dev = true,
    usage = "/msuf versiontest",
    help = "Fake an available update to test the version-check popup.",
    run = function() _G.MSUF_VersionCheck_DebugFakeUpdate() end,
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
            print("|cff00b7ebMSUF|r: " .. M.Tr("First-load module is not loaded."))
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
            print("|cff00b7ebMSUF|r: " .. Fmt("Usage: %s", "/msuf firstload [fresh|upgrade|status]"))
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
        M.InvalidatePage("home")
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
