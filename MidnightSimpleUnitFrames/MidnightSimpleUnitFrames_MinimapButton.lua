--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua"); -- Midnight Simple Unit Frames - Minimap Icon (BugSack-style: LDB + LibDBIcon)
--
-- Behavior:
--  - Left-drag: move icon around the minimap (handled by LibDBIcon)
--  - Right-click: open MSUF menu (same as /msuf)
--  - Shift + Right-click: open MSUF Edit Mode
--
-- Notes:
--  - Preferred: LibDataBroker-1.1 + LibDBIcon-1.0 (BugSack-style).
--  - Fallback: if those libs are missing, MSUF creates its own lightweight minimap
--    button so the icon still exists when ONLY MSUF is loaded.

local addonName = ...

-- -----------------------------------------------------------------------------
-- Backend state (always available)
-- -----------------------------------------------------------------------------

local function EnsureGeneralDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureGeneralDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:19:6");
    if type(_G.MSUF_DB) ~= "table" then
        _G.MSUF_DB = {}
    end
    if type(_G.MSUF_DB.general) ~= "table" then
        _G.MSUF_DB.general = {}
    end
    return Perfy_Trace_Passthrough("Leave", "EnsureGeneralDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:19:6", _G.MSUF_DB.general)
end

local function EnsureMinimapDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureMinimapDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:29:6");
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMinimapDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:29:6"); return general, db
end

-- Local hook that becomes functional once LibDBIcon is present.
local ApplyMinimapIconVisibility = function() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyMinimapIconVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:56:35"); Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyMinimapIconVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:56:35"); end

-- Public API (used later by Options -> Misc toggle). These are defined even if
-- the libs are missing, so calling them never errors.
function _G.MSUF_GetMinimapIconEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_GetMinimapIconEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:60:0");
    local _, db = EnsureMinimapDB()
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_GetMinimapIconEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:60:0", not db.hide)
end

function _G.MSUF_SetMinimapIconEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetMinimapIconEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:65:0");
    local general, db = EnsureMinimapDB()
    general.showMinimapIcon = (enabled and true) or false
    db.hide = (enabled and false) or true
    ApplyMinimapIconVisibility()
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetMinimapIconEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:65:0"); end

function _G.MSUF_ToggleMinimapIcon() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_ToggleMinimapIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:72:0");
    _G.MSUF_SetMinimapIconEnabled(not _G.MSUF_GetMinimapIconEnabled())
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_ToggleMinimapIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:72:0"); end

-- Use our bundled icon in Media.
local ICON_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\MSUF_MinimapIcon.tga"

-- Libs are optional; we support a fallback minimap button when they aren't present.
local libStub = _G.LibStub
local ldb = (libStub and libStub.GetLibrary and libStub:GetLibrary("LibDataBroker-1.1", true)) or nil

local function GetLibDBIcon() Perfy_Trace(Perfy_GetTime(), "Enter", "GetLibDBIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:83:6");
    return Perfy_Trace_Passthrough("Leave", "GetLibDBIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:83:6", (libStub and libStub("LibDBIcon-1.0", true)) or nil)
end

local plugin -- created only when LDB exists

local function ChatMsg(msg) Perfy_Trace(Perfy_GetTime(), "Enter", "ChatMsg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:89:6");
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ChatMsg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:89:6"); end

local function OpenMSUFMenu() Perfy_Trace(Perfy_GetTime(), "Enter", "OpenMSUFMenu file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:95:6");
    -- Opening option UIs in combat can be blocked/tainted.
    if InCombatLockdown and InCombatLockdown() then
        ChatMsg("|cffff5555MSUF: Can't open the menu in combat.|r")
        Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFMenu file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:95:6"); return
    end

    -- Preferred: open the Flash/Slash menu directly.
    if type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage("home")
        Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFMenu file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:95:6"); return
    end

    -- Fallback: some builds expose an options window toggle.
    if type(_G.MSUF_ToggleOptionsWindow) == "function" then
        _G.MSUF_ToggleOptionsWindow("main")
        Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFMenu file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:95:6"); return
    end

    -- Last resort: call slash handler if registered.
    if _G.SlashCmdList then
        local fn = _G.SlashCmdList.MSUFOPTIONS or _G.SlashCmdList.MIDNIGHTSIMPLEUNITFRAMES or _G.SlashCmdList.MIDNIGHTSUF or _G.SlashCmdList.MSUF
        if type(fn) == "function" then
            fn("")
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFMenu file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:95:6"); end

local function OpenMSUFEditMode() Perfy_Trace(Perfy_GetTime(), "Enter", "OpenMSUFEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:123:6");
    if InCombatLockdown and InCombatLockdown() then
        ChatMsg("|cffff5555MSUF: Can't enter Edit Mode in combat.|r")
        Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:123:6"); return
    end

    -- Canonical entry point (preferred; works even when unlinked from Blizzard Edit Mode).
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(true)
        Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:123:6"); return
    end

    -- Legacy fallbacks (older builds / compatibility)
    if type(_G.MSUF_ToggleEditMode) == "function" then
        _G.MSUF_ToggleEditMode()
    elseif type(_G.MSUF_EditMode_Toggle) == "function" then
        _G.MSUF_EditMode_Toggle()
    else
        ChatMsg("|cffff5555MSUF: Edit Mode function not found.|r")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "OpenMSUFEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:123:6"); end

local function Plugin_OnClick(_, button) Perfy_Trace(Perfy_GetTime(), "Enter", "Plugin_OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:145:6");
    -- Keep LeftButton free for LibDBIcon's drag behavior.
    if button == "RightButton" then
        if IsShiftKeyDown and IsShiftKeyDown() then
            OpenMSUFEditMode()
        else
            OpenMSUFMenu()
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Plugin_OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:145:6"); end

local function Plugin_OnTooltipShow(tt) Perfy_Trace(Perfy_GetTime(), "Enter", "Plugin_OnTooltipShow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:156:6");
    if not tt then Perfy_Trace(Perfy_GetTime(), "Leave", "Plugin_OnTooltipShow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:156:6"); return end
    tt:AddLine("Midnight Simple Unit Frames")
    tt:AddLine("Right-click: open /msuf", 0.2, 1, 0.2)
    tt:AddLine("Shift + Right-click: MSUF Edit Mode", 0.2, 1, 0.2)
    tt:AddLine("Left-drag: move icon", 0.2, 1, 0.2)
Perfy_Trace(Perfy_GetTime(), "Leave", "Plugin_OnTooltipShow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:156:6"); end

-- If we have LDB, create the broker data object so LibDBIcon (if present) can render it.
if ldb then
    plugin = ldb:NewDataObject(addonName, {
        type = "data source",
        text = "MSUF",
        icon = ICON_PATH,
    })
    plugin.OnClick = Plugin_OnClick
    plugin.OnTooltipShow = Plugin_OnTooltipShow
end

-- ----------------------------------------------------------------------------
-- Fallback minimap button (no external libs)
-- ----------------------------------------------------------------------------

local fallbackButton
local fallbackDragTicker

local function Fallback_UpdatePosition() Perfy_Trace(Perfy_GetTime(), "Enter", "Fallback_UpdatePosition file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:182:6");
    if not fallbackButton or not Minimap then Perfy_Trace(Perfy_GetTime(), "Leave", "Fallback_UpdatePosition file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:182:6"); return end
    local _, db = EnsureMinimapDB()

    local angle = tonumber(db.minimapPos) or 220
    local radius = tonumber(db.radius) or 80
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius

    fallbackButton:ClearAllPoints()
    fallbackButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
Perfy_Trace(Perfy_GetTime(), "Leave", "Fallback_UpdatePosition file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:182:6"); end

local function Fallback_StopDrag() Perfy_Trace(Perfy_GetTime(), "Enter", "Fallback_StopDrag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:196:6");
    if fallbackDragTicker then
        fallbackDragTicker:Cancel()
        fallbackDragTicker = nil
    end
    if fallbackButton then
        fallbackButton:SetScript("OnUpdate", nil)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Fallback_StopDrag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:196:6"); end

local function Fallback_StartDrag() Perfy_Trace(Perfy_GetTime(), "Enter", "Fallback_StartDrag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:206:6");
    if not fallbackButton or not Minimap then Perfy_Trace(Perfy_GetTime(), "Leave", "Fallback_StartDrag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:206:6"); return end

    -- Update at a modest rate while dragging; no permanent OnUpdate.
    Fallback_StopDrag()
    fallbackDragTicker = (C_Timer and C_Timer.NewTicker) and C_Timer.NewTicker(0.02, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:211:85");
        if not fallbackButton or not fallbackButton._msufDragging then
            Fallback_StopDrag()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:211:85"); return
        end

        local mx, my = Minimap:GetCenter()
        if not mx or not my then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:211:85"); return end

        local cx, cy = GetCursorPosition()
        local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
        cx, cy = cx / scale, cy / scale

        local dx, dy = (cx - mx), (cy - my)
        local angle = math.deg(math.atan2(dy, dx))
        -- Convert to 0..360 and rotate so 0 is "east" like LibDBIcon.
        angle = (angle + 360) % 360

        local _, db = EnsureMinimapDB()
        db.minimapPos = angle
        Fallback_UpdatePosition()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:211:85"); end) or nil
Perfy_Trace(Perfy_GetTime(), "Leave", "Fallback_StartDrag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:206:6"); end

local function EnsureFallbackButton() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureFallbackButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:235:6");
    if fallbackButton or not Minimap or type(CreateFrame) ~= "function" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFallbackButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:235:6"); return fallbackButton
    end

    local b = CreateFrame("Button", "MSUF_MinimapButton", Minimap)
    fallbackButton = b
    b:SetFrameStrata("MEDIUM")
    b:SetSize(32, 32)
    b:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetClampedToScreen(true)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(ICON_PATH)
    b._msufTex = tex

    -- Tooltip
    b:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:254:27");
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            Plugin_OnTooltipShow(GameTooltip)
            GameTooltip:Show()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:254:27"); end)
    b:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:261:27");
        if GameTooltip then GameTooltip:Hide() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:261:27"); end)

    b:SetScript("OnClick", function(_, button) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:265:27");
        -- Keep behavior identical to the broker plugin.
        if button == "RightButton" then
            Plugin_OnClick(nil, "RightButton")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:265:27"); end)

    b:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:272:31");
        if not _G.MSUF_GetMinimapIconEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:272:31"); return end
        self._msufDragging = true
        Fallback_StartDrag()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:272:31"); end)
    b:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:277:30");
        self._msufDragging = false
        Fallback_StopDrag()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:277:30"); end)

    Fallback_UpdatePosition()
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFallbackButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:235:6"); return b
end

-- Now that LibDBIcon exists, wire the visibility applier used by the public API.
ApplyMinimapIconVisibility = function() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyMinimapIconVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:287:29");
    local _, db = EnsureMinimapDB()

    -- Prefer LibDBIcon if available and registered, otherwise fallback button.
    local icon = GetLibDBIcon()
    if icon and plugin then
        if db.hide then
            icon:Hide(addonName)
        else
            icon:Show(addonName)
        end
        -- If we are using LibDBIcon, make sure fallback is hidden.
        if fallbackButton then fallbackButton:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyMinimapIconVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:287:29"); return
    end

    -- No LibDBIcon: use fallback button.
    local b = EnsureFallbackButton()
    if not b then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyMinimapIconVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:287:29"); return end
    if db.hide then
        b:Hide()
    else
        b:Show()
        Fallback_UpdatePosition()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyMinimapIconVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:287:29"); end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:316:23");
    local _, db = EnsureMinimapDB()

    local icon = GetLibDBIcon()
    if icon and plugin then
        icon:Register(addonName, plugin, db)
    else
        EnsureFallbackButton()
    end

    -- Ensure current DB visibility state is applied after registration / creation.
    ApplyMinimapIconVisibility()
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua:316:23"); end)

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_MinimapButton.lua");