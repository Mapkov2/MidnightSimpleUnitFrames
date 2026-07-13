--- Menu2 public globals, slash routing, and combat-hide bridge.
--- This file is the compatibility facade for older slash/global entry points. Keep it thin:
--- open/toggle/select calls delegate to Menu2, and combat entry hides the menu safely.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local M = MSUF.MSUF2 or _G.MSUF2
if not M then return end

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

local function OpenExactSettingControl(settingKey, fallbackLabel, fallbackPage)
    settingKey = tostring(settingKey or "")
    fallbackPage = tostring(fallbackPage or "")
    if settingKey == "" then return false, "Which exact MSUF option do you want me to open?" end
    if M.BlockCombatAction and M.BlockCombatAction() then
        return false, "I cannot open and focus an options control during combat. Try again after combat."
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
    local bridge = M.SearchBridge
    if bridge and type(bridge.OpenSearchTarget) == "function" then
        local called, opened, focused, exact = bridge.OpenSearchTarget(page, query, label, widget, nil, {
            settingKey = settingKey,
        })
        if called and opened == false then
            return false, "I could not open the MSUF options page for " .. label .. "."
        end
        if called and focused == false then
            return false, "I opened " .. page .. ", but its exact " .. label .. " control is not available there anymore."
        end
        if called and exact == false then
            return true, "Opened the MSUF page and highlighted the closest matching control for " .. label .. "."
        end
    elseif type(M.SelectPage) == "function" then
        M.SelectPage(page)
    end
    return true, "Opened " .. label .. " and focused its exact control."
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
        return (win and win.IsShown and win:IsShown())
            or (bar and bar.IsShown and bar:IsShown())
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
SLASH_MSUF2OPTIONS1 = "/msuf"
SlashCmdList["MSUF2OPTIONS"] = function(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = msg:lower()
    local cmd = msg:match("^(%S+)") or ""
    if cmd == "versiontest" then
        if type(_G.MSUF_VersionCheck_DebugFakeUpdate) == "function" then
            _G.MSUF_VersionCheck_DebugFakeUpdate()
        else
            print("|cffffd700MSUF:|r Version test helper is not loaded.")
        end
        return
    end
    if cmd == "inputdebug" then
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then _G.SlashCmdList["MIDNIGHTSUF"](msg) end
        return
    end
    if cmd == "tour" or cmd == "guide" or cmd == "setup" then
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
        return
    end
    if cmd == "firstload" then
        local firstLoad = MSUF and MSUF.FirstLoad6
        if type(firstLoad) ~= "table" or type(firstLoad.Reset) ~= "function" then
            print("|cff00b7ebMSUF|r: First-load module is not loaded.")
            return
        end
        local arg = msg:match("^%S+%s+(%S+)") or ""
        if arg == "status" then
            local shows = type(firstLoad.ShouldShowDashboard) == "function" and firstLoad:ShouldShowDashboard()
            local state = type(firstLoad.GetState) == "function" and firstLoad:GetState() or {}
            local detection = type(firstLoad.GetDetection) == "function" and firstLoad:GetDetection() or {}
            print(string.format("|cff00b7ebMSUF|r first-load: status=%s step=%s install=%s shows=%s reason=%s profile=%s legacy=%s schema=%s rawDB=%s rawProfiles=%s",
                tostring(state.status), tostring(state.step), tostring(state.installKind),
                tostring(shows), tostring(detection.reason), tostring(detection.existingProfile),
                tostring(detection.legacyProfile), tostring(detection.profileSchema or "none"),
                tostring(detection.rawDB), tostring(detection.rawProfiles)))
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
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
        M.Open("home")
        print("|cff00b7ebMSUF|r: First-start welcome re-armed (" .. tostring(firstLoad:GetInstallKind()) .. "). Guided-tour progress was reset.")
        return
    end
    if cmd == "help" or cmd == "reset" or cmd == "fullreset" or cmd == "absorb" or cmd == "analytics" then
        if cmd ~= "help" and M.BlockCombatAction and M.BlockCombatAction() then return end
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then _G.SlashCmdList["MIDNIGHTSUF"](msg) end
        return
    end
    if msg == "locale" or msg == "locales" or msg == "loc" then
        local total, missing = 0, 0
        if type(M.GetLocaleCoverage) == "function" then total, missing = M.GetLocaleCoverage() end
        local locale = MSUF.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
        print(string.format("|cff00b7ebMSUF2|r locale %s: %d keys seen, %d missing translations.", locale, total or 0, missing or 0))
        return
    end
    local aliases = M.ALIASES or {}
    M.Open(aliases[msg] or (msg ~= "" and msg or nil))
end
SLASH_MSUFOPTIONS1 = SLASH_MSUFOPTIONS1 or "/msufoptions"
SlashCmdList["MSUFOPTIONS"] = SlashCmdList["MSUFOPTIONS"] or function(msg)
    local aliases = M.ALIASES or {}
    local pageKey = aliases[tostring(msg or ""):lower()]
    M.Open(pageKey)
end

-- Stable integration points for Edit Mode and external launchers. Resolve the
-- controller at click time because it is loaded after all Menu2 pages.
ExportPublic("MSUF_StartGuidedTour", function(opts)
    return type(M.StartGuidedTour) == "function" and M.StartGuidedTour(opts)
end)
ExportPublic("MSUF_ResumeGuidedTour", function()
    return type(M.ResumeGuidedTour) == "function" and M.ResumeGuidedTour()
end)
