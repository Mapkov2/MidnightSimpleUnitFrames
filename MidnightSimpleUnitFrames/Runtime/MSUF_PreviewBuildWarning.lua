--- Preserve the existing 6.0 preview login notice without eagerly loading the
--- options addon. The menu keeps its separate on-open notice.
---
--- Stays independent of the welcome message and of its Global > Misc toggle:
--- this build can be installed on a live retail client whose region has not
--- received 12.1 yet, so the "built for 12.1" notice must not be silenceable.
---
--- Do not remove, fold into the welcome message, or gate behind a setting
--- before 2026-08-14, the date 12.1 goes live in every region. Until then a
--- download from CurseForge can land on a pre-12.1 client in some regions.

local addonName = ...
local PREVIEW_WARNING_LINES = {
    "|cffffd700MSUF 6.0 Beta|r · Built for WoW 12.1 PTR.",
    "|cffffd700Auras|r use Blizzard's native 12.1 system.",
    "|cff40ff40Thanks for testing!|r Report bugs on Discord or GitHub.",
}

local function IsMSUF60PreviewBuild()
    local getMeta = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
    local version
    if type(getMeta) == "function" then
        version = getMeta(addonName or "MidnightSimpleUnitFrames", "Version")
    elseif type(_G.GetAddOnMetadata) == "function" then
        version = _G.GetAddOnMetadata(addonName or "MidnightSimpleUnitFrames", "Version")
    end
    if type(version) ~= "string" or not version:match("^6%.0") then return false end
    local lower = version:lower()
    return (lower:find("alpha", 1, true)
        or lower:find("preview", 1, true)
        or lower:find("pre", 1, true)
        or lower:find("beta", 1, true)) and true or false
end

local function ShowPreviewLoginWarning()
    local chat = _G.DEFAULT_CHAT_FRAME
    for i = 1, #PREVIEW_WARNING_LINES do
        if chat and type(chat.AddMessage) == "function" then
            chat:AddMessage(PREVIEW_WARNING_LINES[i])
        elseif type(_G.print) == "function" then
            _G.print(PREVIEW_WARNING_LINES[i])
        end
    end
end

if IsMSUF60PreviewBuild() and type(_G.CreateFrame) == "function" then
    local loginWarningFrame = _G.CreateFrame("Frame")
    loginWarningFrame:RegisterEvent("PLAYER_LOGIN")
    loginWarningFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        _G.C_Timer.After(2, ShowPreviewLoginWarning)
    end)
end
