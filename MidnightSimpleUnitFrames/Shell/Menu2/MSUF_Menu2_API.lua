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
        bridge.OpenSearchTarget(page, query, label, widget)
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
    local bugReportCombat = ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
    if cmd == "versiontest" then
        if type(_G.MSUF_VersionCheck_DebugFakeUpdate) == "function" then
            _G.MSUF_VersionCheck_DebugFakeUpdate()
        else
            print("|cffffd700MSUF:|r Version test helper is not loaded.")
        end
        return
    end
    if cmd == "bugdummy" then
        if bugReportCombat then
            print("|cffffd700MSUF:|r Bug report generation is deferred while combat lockdown is active. Run /msuf bugdummy after combat.")
            return
        end
        if type(_G.MSUF_BugReport_TriggerDummy) == "function" then
            local report, reason = _G.MSUF_BugReport_TriggerDummy()
            if not report then
                print("|cffffd700MSUF:|r Bug report dummy was not created" .. (reason and (": " .. tostring(reason)) or "."))
                return
            end
            print("|cff00b7ebMSUF:|r Dummy bug report created. Open the Dashboard bug report panel to copy it.")
            M.Open("home")
        else
            print("|cffffd700MSUF:|r Bug report helper is not loaded.")
        end
        return
    end
    if cmd == "bug" or cmd == "bugreport" then
        if bugReportCombat then
            print("|cffffd700MSUF:|r Bug report generation is deferred while combat lockdown is active. Open it after combat.")
            return
        end
        if type(_G.MSUF_BugReport_OpenManual) == "function" then
            _G.MSUF_BugReport_OpenManual()
        else
            M.SetMenuStateValue("dashboardBugReportOpen", true)
        end
        M.Open("home")
        return
    end
    if cmd == "inputdebug" then
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then _G.SlashCmdList["MIDNIGHTSUF"](msg) end
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
