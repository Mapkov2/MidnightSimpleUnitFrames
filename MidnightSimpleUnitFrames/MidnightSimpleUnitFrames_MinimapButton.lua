-- Midnight Simple Unit Frames - Minimap Icon (BugSack-style: LDB + LibDBIcon)
--
-- Behavior:
--  - Left-drag: move icon around the minimap (handled by LibDBIcon)
--  - Right-click: open MSUF menu (same as /msuf)
--  - Shift + Right-click: open MSUF Edit Mode
--
-- Notes:
--  - Requires LibDataBroker-1.1 and LibDBIcon-1.0.
--  - If the libs are missing, this file becomes a safe no-op (no errors, no frames).

local addonName = ...

-- -----------------------------------------------------------------------------
-- Backend state (always available)
-- -----------------------------------------------------------------------------

local function EnsureGeneralDB()
    if type(_G.MSUF_DB) ~= "table" then
        _G.MSUF_DB = {}
    end
    if type(_G.MSUF_DB.general) ~= "table" then
        _G.MSUF_DB.general = {}
    end
    return _G.MSUF_DB.general
end

local function EnsureMinimapDB()
    local general = EnsureGeneralDB()

    local db = general.minimapIconDB
    if type(db) ~= "table" then
        db = { hide = false }
        general.minimapIconDB = db
    end

    -- Canonical, future-friendly toggle for Options -> Misc.
    if general.showMinimapIcon == false then
        db.hide = true
    elseif general.showMinimapIcon == true then
        db.hide = false
    elseif db.hide == nil then
        db.hide = false
    end

    -- Defaults expected by LibDBIcon (kept even if libs are missing, so the toggle
    -- can be implemented without touching this file later).
    if db.minimapPos == nil then db.minimapPos = 220 end
    if db.radius == nil then db.radius = 80 end

    return general, db
end

-- Local hook that becomes functional once LibDBIcon is present.
local ApplyMinimapIconVisibility = function() end

-- Public API (used later by Options -> Misc toggle). These are defined even if
-- the libs are missing, so calling them never errors.
function _G.MSUF_GetMinimapIconEnabled()
    local _, db = EnsureMinimapDB()
    return not db.hide
end

function _G.MSUF_SetMinimapIconEnabled(enabled)
    local general, db = EnsureMinimapDB()
    general.showMinimapIcon = (enabled and true) or false
    db.hide = (enabled and false) or true
    ApplyMinimapIconVisibility()
end

function _G.MSUF_ToggleMinimapIcon()
    _G.MSUF_SetMinimapIconEnabled(not _G.MSUF_GetMinimapIconEnabled())
end

local libStub = _G.LibStub
if not libStub then
    return
end

local ldb = libStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then
    return
end

-- Use our bundled icon in Media (no extension needed in WoW).
local ICON_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\MSUF_MinimapIcon.tga"

local plugin = ldb:NewDataObject(addonName, {
    type = "data source",
    text = "MSUF",
    icon = ICON_PATH,
})

local function ChatMsg(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

local function OpenMSUFMenu()
    -- Opening option UIs in combat can be blocked/tainted.
    if InCombatLockdown and InCombatLockdown() then
        ChatMsg("|cffff5555MSUF: Can't open the menu in combat.|r")
        return
    end

    -- Preferred: open the Flash/Slash menu directly.
    if type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage("home")
        return
    end

    -- Fallback: some builds expose an options window toggle.
    if type(_G.MSUF_ToggleOptionsWindow) == "function" then
        _G.MSUF_ToggleOptionsWindow("main")
        return
    end

    -- Last resort: call slash handler if registered.
    if _G.SlashCmdList then
        local fn = _G.SlashCmdList.MSUFOPTIONS or _G.SlashCmdList.MIDNIGHTSIMPLEUNITFRAMES or _G.SlashCmdList.MIDNIGHTSUF or _G.SlashCmdList.MSUF
        if type(fn) == "function" then
            fn("")
        end
    end
end

local function OpenMSUFEditMode()
    if InCombatLockdown and InCombatLockdown() then
        ChatMsg("|cffff5555MSUF: Can't enter Edit Mode in combat.|r")
        return
    end

    -- Canonical entry point (preferred; works even when unlinked from Blizzard Edit Mode).
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(true)
        return
    end

    -- Legacy fallbacks (older builds / compatibility)
    if type(_G.MSUF_ToggleEditMode) == "function" then
        _G.MSUF_ToggleEditMode()
    elseif type(_G.MSUF_EditMode_Toggle) == "function" then
        _G.MSUF_EditMode_Toggle()
    else
        ChatMsg("|cffff5555MSUF: Edit Mode function not found.|r")
    end
end

function plugin.OnClick(_, button)
    -- Keep LeftButton free for LibDBIcon's drag behavior.
    if button == "RightButton" then
        if IsShiftKeyDown and IsShiftKeyDown() then
            OpenMSUFEditMode()
        else
            OpenMSUFMenu()
        end
    end
end

function plugin.OnTooltipShow(tt)
    if not tt then return end
    tt:AddLine("Midnight Simple Unit Frames")
    tt:AddLine("Right-click: open /msuf", 0.2, 1, 0.2)
    tt:AddLine("Shift + Right-click: MSUF Edit Mode", 0.2, 1, 0.2)
    tt:AddLine("Left-drag: move icon", 0.2, 1, 0.2)
end

local function GetLibDBIcon()
    return libStub("LibDBIcon-1.0", true)
end

-- Now that LibDBIcon exists, wire the visibility applier used by the public API.
ApplyMinimapIconVisibility = function()
    local icon = GetLibDBIcon()
    if not icon then
        return
    end

    local _, db = EnsureMinimapDB()
    if db.hide then
        icon:Hide(addonName)
    else
        icon:Show(addonName)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local icon = GetLibDBIcon()
    if not icon then
        return
    end

    local _, db = EnsureMinimapDB()
    icon:Register(addonName, plugin, db)

    -- Ensure current DB visibility state is applied after registration.
    ApplyMinimapIconVisibility()
end)
