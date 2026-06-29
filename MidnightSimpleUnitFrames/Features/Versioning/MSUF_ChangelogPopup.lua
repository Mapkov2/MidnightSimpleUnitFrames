--- MSUF_ChangelogPopup.lua
--- One-shot bundled changelog prompt. No runtime work after the login check.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local KEY = "MSUF_ChangelogPopup"
local POPUP_KEY = "MSUF_CHANGELOG_POPUP"

local type, tostring = type, tostring

local function ChangelogData()
    local data = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" then return nil end
    if type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then return nil end
    return data
end

local function CurrentVersion(data)
    local version = data and data.currentVersion
    if type(version) == "string" and version ~= "" then return version end
    local entry = data and data.entries and data.entries[1]
    version = entry and entry.version
    if type(version) == "string" and version ~= "" then return version end
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        version = _G.C_AddOns.GetAddOnMetadata(addonName, "Version")
        if type(version) == "string" and version ~= "" then return version end
    end
    return nil
end

local function GlobalChangelogState()
    ExportPublic("MSUF_GlobalDB", _G.MSUF_GlobalDB or {})
    local gdb = _G.MSUF_GlobalDB
    gdb.global = (type(gdb.global) == "table") and gdb.global or {}
    gdb.global.changelog = (type(gdb.global.changelog) == "table") and gdb.global.changelog or {}
    return gdb.global.changelog
end

local function MarkSeen(version)
    if not version then return end
    local state = GlobalChangelogState()
    state.lastSeenVersion = tostring(version)
end

local function OpenDashboardChangelog()
    local M = _G.MSUF2 or (type(MSUF) == "table" and MSUF.MSUF2)
    if M then
        if type(M.SetMenuStateValue) == "function" then
            M.SetMenuStateValue("dashboardChangelogOpen", true)
        else
            M.dashboardChangelogOpen = true
        end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
        if type(M.Open) == "function" then return M.Open("home") end
    end
    if type(_G.MSUF2_Open) == "function" then
        _G.MSUF2_Open("home")
        return true
    elseif type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        _G.MSUF_OpenStandaloneOptionsWindow("home")
        return true
    elseif type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage("home")
        return true
    end
    return false
end

local function PopupText(data, version)
    local label = (data and data.rangeLabel) or version
    return "MSUF updated to " .. tostring(version) .. ".\n"
        .. "Bundled release notes are available in the dashboard.\n\n"
        .. "Open changelog now?"
        .. ((label and label ~= version) and ("\n\n" .. tostring(label)) or "")
end

local function InstallPopup()
    if not _G.StaticPopupDialogs then return false end
    if _G.StaticPopupDialogs[POPUP_KEY] then return true end

    local spec = {
        text = "%s",
        button1 = "Open Changelog",
        button2 = _G.CLOSE or "Close",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(_, data)
            if data and data.version then MarkSeen(data.version) end
            OpenDashboardChangelog()
        end,
        OnCancel = function(_, data)
            if data and data.version then MarkSeen(data.version) end
        end,
    }

    local M = _G.MSUF2 or (type(MSUF) == "table" and MSUF.MSUF2)
    if M and type(M.InstallStaticPopup) == "function" then
        M.InstallStaticPopup(POPUP_KEY, spec)
    else
        _G.StaticPopupDialogs[POPUP_KEY] = spec
    end
    return true
end

local function ShouldShow(force)
    local data = ChangelogData()
    if not data then return false end
    local version = CurrentVersion(data)
    if not version then return false end
    if force == true then return true, data, version end
    local state = GlobalChangelogState()
    return state.lastSeenVersion ~= tostring(version), data, version
end

local function Show(force)
    local shouldShow, data, version = ShouldShow(force)
    if not shouldShow then return false end

    if InstallPopup() and _G.StaticPopup_Show then
        _G.StaticPopup_Show(POPUP_KEY, PopupText(data, version), nil, { version = version })
        return true
    end

    MarkSeen(version)
    if print then
        print("|cff7aa2f7MSUF|r: Updated to " .. tostring(version) .. ". Open /msuf to view the changelog.")
    end
    return false
end

local function Init()
    local bus = MSUF.MSUF_EventBus or _G.MSUF_EventBus
    if bus and type(bus.Register) == "function" then
        bus:Register("PLAYER_ENTERING_WORLD", KEY .. "_PEW", function()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(2, Show)
            else
                Show()
            end
        end, nil, true)
        return
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(2, Show)
        else
            Show()
        end
    end)
end

if type(MSUF.MSUF_RegisterModule) == "function" then
    MSUF.MSUF_RegisterModule("ChangelogPopup", {
        key = "ChangelogPopup",
        order = 1000,
        enabled = true,
        Init = Init,
    })
else
    Init()
end

ExportPublic("MSUF_ShowChangelogPopup", function(force)
    return Show(force ~= false)
end)
