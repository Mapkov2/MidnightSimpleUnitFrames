--- Menu2 public globals, slash routing, and combat-hide bridge.

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
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function()
        local win = M.frame
        local bar = M.minimizedBar
        local visible = (win and win.IsShown and win:IsShown())
            or (bar and bar.IsShown and bar:IsShown())
        if not visible then return end
        if M.BlockCombatAction then M.BlockCombatAction() end
        if M.HideSlashMenuAndMinibar then M.HideSlashMenuAndMinibar(win) end
    end)
end

SLASH_MSUF2OPTIONS1 = "/msuf"
SlashCmdList["MSUF2OPTIONS"] = function(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = msg:lower()
    local cmd = msg:match("^(%S+)") or ""
    if cmd == "versiontest" then
        if type(_G.MSUF_VersionCheck_DebugFakeUpdate) == "function" then
            pcall(_G.MSUF_VersionCheck_DebugFakeUpdate)
        else
            print("|cffffd700MSUF:|r Version test helper is not loaded.")
        end
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
