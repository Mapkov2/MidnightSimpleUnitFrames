--- One unified login greeting in the addon's own brand colors, printed without
--- eagerly loading the options addon.
---
--- Gated by Global > Misc "Show welcome message" (general.showWelcomeMessage,
--- default on). This is the only startup chat notice owned by MSUF.
--- Preview builds keep the compatibility part visible on clients older than
--- 12.1, even when the optional welcome content is disabled.
---
--- Cost profile: one PLAYER_LOGIN handler that drops both its event and its
--- script after the first dispatch, one 2s timer, up to four chat lines. Nothing
--- polls, nothing survives login, and no protected or layout write is involved.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local _G = _G
local type, rawget, format = type, rawget, string.format

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

--- Brand colors: the two title colors from the TOC plus the Menu2 theme's
--- `muted` ramp, so the login lines read as MSUF instead of a generic print.
local BRAND = "|cff38c7f0"
local BRAND_SOFT = "|cffcce0ff"
local MUTED = "|cffa8b4c7"
local ACCENT = "|cffffd700"
local STOP = "|r"
local DOT = "\194\183"
local PREVIEW_BUILD_KEY = "|cffffd700MSUF 6.0 RC18|r \194\183 Built for WoW 12.1 PTR."
local PREVIEW_AURAS_KEY = "|cffffd700Auras|r use Blizzard's native 12.1 system."
local PREVIEW_THANKS_KEY = "|cff40ff40Thanks for testing!|r Report bugs on Discord or GitHub."

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    local locale = MSUF.L or _G.MSUF_L
    local translated = type(locale) == "table" and rawget(locale, text)
    return translated or text
end

local function AddonVersion()
    local getMeta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getMeta) ~= "function" then return nil end
    local version = getMeta(addonName or "MidnightSimpleUnitFrames", "Version")
    if type(version) == "string" and version ~= "" then return version end
    return nil
end

local function IsMSUF60PreviewBuild(version)
    if type(version) ~= "string" or not version:match("^6%.0") then return false end
    local lower = version:lower()
    return (lower:find("alpha", 1, true)
        or lower:find("preview", 1, true)
        or lower:find("pre", 1, true)
        or lower:find("rc", 1, true)
        or lower:find("beta", 1, true)) and true or false
end

local function PlainText(text)
    text = Tr(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function PreviewBuildText()
    local text = PlainText(PREVIEW_BUILD_KEY)
    text = text:gsub("^MSUF 6%.0 RC18", "", 1):gsub("^%s+", "", 1)
    if text:sub(1, #DOT) == DOT then
        text = text:sub(#DOT + 1):gsub("^%s+", "", 1)
    end
    return text
end

--- Major.minor of the running client, so the greeting names the current patch
--- instead of a literal that goes stale on the next one. Plain client metadata,
--- never a secret value.
local function ClientPatch()
    local getBuildInfo = _G.GetBuildInfo
    if type(getBuildInfo) ~= "function" then return "12.1" end
    local version = getBuildInfo()
    if type(version) ~= "string" then return "12.1" end
    return version:match("^(%d+%.%d+)") or "12.1"
end

local function IsClientAtLeast(requiredMajor, requiredMinor)
    local getBuildInfo = _G.GetBuildInfo
    if type(getBuildInfo) ~= "function" then return false end
    local version = getBuildInfo()
    if type(version) ~= "string" then return false end
    local major, minor = version:match("^(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)
    if not major or not minor then return false end
    return major > requiredMajor or (major == requiredMajor and minor >= requiredMinor)
end

local function PreviewWarningRequired()
    return IsMSUF60PreviewBuild(AddonVersion()) and not IsClientAtLeast(12, 1)
end

local function WelcomeLines(warningOnly)
    local title = BRAND .. "Midnight" .. STOP .. " " .. BRAND_SOFT .. "Simple Unit Frames" .. STOP
    local version = AddonVersion()
    if version then
        title = title .. " " .. MUTED .. "v" .. version .. STOP
    end

    --- `/msuf` closes its own color and reopens the muted one, so the rest of the
    --- hint keeps a single color regardless of how the client nests |r.
    local slash = ACCENT .. "/msuf" .. STOP .. MUTED

    local lines = { title }
    if IsMSUF60PreviewBuild(version) then
        lines[#lines + 1] = MUTED .. PreviewBuildText() .. " " .. DOT .. " "
            .. PlainText(PREVIEW_AURAS_KEY) .. STOP
        if not warningOnly then
            lines[#lines + 1] = MUTED .. PlainText(PREVIEW_THANKS_KEY) .. STOP
        end
    else
        lines[#lines + 1] = BRAND_SOFT .. format(Tr("Welcome to Patch %s"), ClientPatch()) .. STOP
            .. " " .. MUTED .. DOT .. STOP
            .. " " .. BRAND .. Tr("Thank you for using MSUF.") .. STOP
    end
    if not warningOnly then
        lines[#lines + 1] = MUTED .. format(Tr("Type %s to open the menu."), slash) .. STOP
    end
    return lines
end

local function WelcomeEnabled()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general
    if type(general) ~= "table" then return true end
    return general.showWelcomeMessage ~= false
end

local function ShowWelcomeMessage(force)
    local welcomeEnabled = force == true or WelcomeEnabled()
    if not welcomeEnabled and not PreviewWarningRequired() then return false end

    local chat = _G.DEFAULT_CHAT_FRAME
    local lines = WelcomeLines(not welcomeEnabled)
    for i = 1, #lines do
        if chat and type(chat.AddMessage) == "function" then
            chat:AddMessage(lines[i])
        elseif type(_G.print) == "function" then
            _G.print(lines[i])
        end
    end
    return true
end

if type(_G.CreateFrame) == "function" then
    local welcomeFrame = _G.CreateFrame("Frame")
    welcomeFrame:RegisterEvent("PLAYER_LOGIN")
    welcomeFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        self:SetScript("OnEvent", nil)
        --- Delayed so the greeting lands after Blizzard's own login spam, and
        --- late enough for SavedVariables to have seeded the toggle.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(2, ShowWelcomeMessage)
        else
            ShowWelcomeMessage()
        end
    end)
end

MSUF.WelcomeMessage = {
    GetLines = WelcomeLines,
    IsEnabled = WelcomeEnabled,
    IsPreviewWarningRequired = PreviewWarningRequired,
    Show = ShowWelcomeMessage,
}

--- Debug: /run MSUF_ShowWelcomeMessage() replays it even with the toggle off.
ExportPublic("MSUF_ShowWelcomeMessage", function(force)
    return ShowWelcomeMessage(force ~= false)
end)
