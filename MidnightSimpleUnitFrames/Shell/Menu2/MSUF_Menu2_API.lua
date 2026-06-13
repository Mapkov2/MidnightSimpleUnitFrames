--- Menu2 public globals, slash routing, and combat-hide bridge.
--- This file is the compatibility facade for older slash/global entry points. Keep it thin:
--- open/toggle/select calls delegate to Menu2, and combat entry hides the menu safely.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2
if not M then return end

_G.MSUF2_Open = function(pageKey) M.Open(pageKey) end
_G.MSUF2_Toggle = function(pageKey) M.Toggle(pageKey) end

_G.MSUF_OpenStandaloneOptionsWindow = function(pageKey) M.Open(pageKey or "home") end
_G.MSUF_ShowStandaloneOptionsWindow = function(pageKey) M.Open(pageKey or "home") end
_G.MSUF_HideStandaloneOptionsWindow = function()
    if M.HideSlashMenuAndMinibar then M.HideSlashMenuAndMinibar(M.frame) end
end
_G.MSUF_OpenOptionsMenu = function() M.Open("home") end
_G.MSUF_OpenPage = function(pageKey) return M.SelectPage(pageKey or "home") end
_G.MSUF_SwitchMirrorPage = function(pageKey) return M.SelectPage(pageKey or "home") end
_G.MSUF_GetCurrentMirrorPage = function() return M.activeKey or "home" end
_G.MSUF_GetMirrorPages = function() return M.pages end

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
            if M.BlockCombatAction then M.BlockCombatAction() end
            if M.HideSlashMenuAndMinibar then M.HideSlashMenuAndMinibar(win) end
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
            pcall(_G.MSUF_VersionCheck_DebugFakeUpdate)
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
            local ok, report, reason = pcall(_G.MSUF_BugReport_TriggerDummy)
            if not ok or not report then
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
            pcall(_G.MSUF_BugReport_OpenManual)
        else
            M.dashboardBugReportOpen = true
            if type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue("dashboardBugReportOpen", true)
            end
        end
        M.Open("home")
        return
    end
    if cmd == "help" or cmd == "reset" or cmd == "fullreset" or cmd == "absorb" or cmd == "analytics" then
        if cmd ~= "help" and M.BlockCombatAction and M.BlockCombatAction() then return end
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], msg)
        end
        return
    end
    if msg == "locale" or msg == "locales" or msg == "loc" then
        local total, missing = 0, 0
        if type(M.GetLocaleCoverage) == "function" then
            total, missing = M.GetLocaleCoverage()
        end
        local locale = MSUF.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
        print(string.format("|cff00b7ebMSUF2|r locale %s: %d keys seen, %d missing translations.", locale, total or 0, missing or 0))
        return
    end
    local aliases = M.ALIASES or {}
    M.Open(aliases[msg] or msg or "home")
end

SLASH_MSUFOPTIONS1 = SLASH_MSUFOPTIONS1 or "/msufoptions"
SlashCmdList["MSUFOPTIONS"] = SlashCmdList["MSUFOPTIONS"] or function(msg)
    local aliases = M.ALIASES or {}
    M.Open(aliases[tostring(msg or ""):lower()] or "home")
end
