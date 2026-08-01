--- MSUF_ClientVersionWarning.lua
--- One acknowledgement popup per login/reload while the client is older than
--- 12.1. Auras, dispels and several other subsystems are built on 12.1 APIs and
--- stay dark on 12.0 clients, so users who update early get told once instead of
--- filing bug reports.
---
--- Cost profile — nothing here can ever run in combat:
--- * One GetBuildInfo() read at file load, cached for the session.
--- * 12.1 and newer stop right there: no event hook, no timer, no frame, and no
---   module-registry entry, so the ApplyModules/RefreshModuleSettings fanouts
---   never walk a dead module.
--- * 12.0 arms a single once=true PLAYER_ENTERING_WORLD handler. The EventBus
---   drops it after the first dispatch and unregisters the driver event when no
---   other listener remains, so the residual cost after login is zero.
--- * No OnUpdate, no polling, no hooksecurefunc, no protected/layout writes, so
---   there is no taint surface and no combat gating is required.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local KEY = "MSUF_ClientVersionWarning"
local POPUP_KEY = "MSUF_CLIENT_VERSION_WARNING"

--- Interface number of the first Midnight 12.1 client. Anything below it is a
--- 12.0 client that cannot run the 12.1-only feature set.
local MIN_INTERFACE = 120100

local type, tonumber, rawget, select = type, tonumber, rawget, select

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    local locale = MSUF.L or _G.MSUF_L
    local translated = type(locale) == "table" and rawget(locale, text)
    return translated or text
end

--- Read exactly once per session, at file load. The build cannot change while
--- the client runs, so nothing below ever queries the API again.
--- Secret-safe: GetBuildInfo returns plain client metadata, never unit data.
local interfaceNumber
do
    local getBuildInfo = _G.GetBuildInfo
    if type(getBuildInfo) == "function" then
        interfaceNumber = tonumber((select(4, getBuildInfo())))
    end
end

--- Only a positively detected pre-12.1 build warns. An unreadable build stays
--- silent so odd environments never get a popup they cannot act on.
local isLegacyClient = (interfaceNumber ~= nil) and (interfaceNumber < MIN_INTERFACE) or false

local function ClientInterfaceNumber()
    return interfaceNumber
end

local function IsLegacyClient()
    return isLegacyClient
end

local function PopupText()
    return Tr("Midnight Simple Unit Frames requires World of Warcraft 12.1.")
        .. "\n\n"
        .. Tr("Your client is still on an earlier build. Auras, dispel highlighting and several other features stay disabled until patch 12.1 goes live.")
        .. "\n\n"
        .. Tr("Everything else keeps working normally — no action is needed.")
end

local function InstallPopup()
    if not _G.StaticPopupDialogs then return false end
    if _G.StaticPopupDialogs[POPUP_KEY] then return true end

    local spec = {
        text = "%s",
        button1 = _G.OKAY or "Okay",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    local M = _G.MSUF2 or (type(MSUF) == "table" and MSUF.MSUF2)
    if M and type(M.InstallStaticPopup) == "function" then
        M.InstallStaticPopup(POPUP_KEY, spec)
    else
        _G.StaticPopupDialogs[POPUP_KEY] = spec
    end
    return true
end

local shownThisSession = false

local function Show(force)
    if force ~= true then
        if shownThisSession then return false end
        if not IsLegacyClient() then return false end
    end
    shownThisSession = true

    if InstallPopup() and _G.StaticPopup_Show then
        _G.StaticPopup_Show(POPUP_KEY, PopupText())
        return true
    end

    if print then
        print("|cff7aa2f7MSUF|r: " .. (PopupText():gsub("\n\n", " ")))
    end
    return false
end

local wired = false

--- Wired at file load, not from the module registry: nothing in the addon calls
--- MSUF_InitModules, so a registry Init hook would never run.
local function Init()
    if wired then return end
    --- 12.1 and newer never arms the module, so there is no login-path cost.
    if not IsLegacyClient() then return end
    wired = true

    local bus = MSUF.MSUF_EventBus or _G.MSUF_EventBus
    if bus and type(bus.Register) == "function" then
        bus:Register("PLAYER_ENTERING_WORLD", KEY .. "_PEW", function()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(1.5, Show)
            else
                Show()
            end
        end, nil, true)
        return
    end

    --- Fallback only: drops both the event and the script so the frame is inert
    --- once it has fired.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        self:SetScript("OnEvent", nil)
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(1.5, Show)
        else
            Show()
        end
    end)
end

--- Only a legacy client registers: on 12.1 the module array stays untouched, so
--- the ApplyModules / RefreshModuleSettings fanouts never walk a dead entry.
if isLegacyClient and type(MSUF.MSUF_RegisterModule) == "function" then
    MSUF.MSUF_RegisterModule("ClientVersionWarning", {
        key = "ClientVersionWarning",
        order = 998,
        enabled = true,
        Init = Init,
    })
end

Init()

MSUF.ClientVersionWarning = {
    MIN_INTERFACE = MIN_INTERFACE,
    GetInterfaceNumber = ClientInterfaceNumber,
    IsLegacyClient = IsLegacyClient,
    GetPopupText = PopupText,
    Show = Show,
}

--- Debug: /run MSUF_ShowClientVersionWarning() forces the popup on any client.
ExportPublic("MSUF_ShowClientVersionWarning", function(force)
    return Show(force ~= false)
end)
