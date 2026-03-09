-- MSUF_AddonCompartment.lua
-- Addon Compartment integration for WoW 12.0 Midnight.
--
-- The Addon Compartment is a built-in UI element (top-right minimap area)
-- that lists all addons declaring AddonCompartmentFunc in their TOC.
-- This is the primary discovery mechanism for addons in 12.0.
--
-- Secret-safe: no comparisons or arithmetic on protected values.
-- Zero overhead: no events, no OnUpdate, only fires on user click/hover.

local addonName, ns = ...

-- =========================================================================
-- Click handler: Left = open menu, Right = toggle Edit Mode
-- =========================================================================
function MSUF_AddonCompartment_OnClick(_, btn)
    if btn == "RightButton" then
        -- Toggle Edit Mode
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            local st = _G.MSUF_EditState
            local nextActive = true
            if type(st) == "table" and st.active ~= nil then
                nextActive = not st.active
            end
            pcall(_G.MSUF_SetMSUFEditModeDirect, nextActive, nil)
        elseif type(_G.MSUF_ToggleEditMode) == "function" then
            pcall(_G.MSUF_ToggleEditMode)
        end
    else
        -- Open MSUF menu
        if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
            pcall(_G.MSUF_OpenStandaloneOptionsWindow, "home")
        elseif type(_G.MSUF_OpenOptionsMenu) == "function" then
            pcall(_G.MSUF_OpenOptionsMenu)
        end
    end
end

-- =========================================================================
-- Tooltip: show version, profile, edit mode status
-- =========================================================================
function MSUF_AddonCompartment_OnEnter(_, menuButtonFrame)
    local tt = _G.GameTooltip
    if not tt then return end

    tt:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    tt:AddLine("Midnight Simple Unit Frames", 1, 1, 1)

    -- Version
    local version = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
        and _G.C_AddOns.GetAddOnMetadata(addonName, "Version")
    if type(version) == "string" and version ~= "" then
        tt:AddLine("Version: " .. version, 0.6, 0.6, 0.6)
    end

    -- Active profile
    local profile = _G.MSUF_ActiveProfile
    if type(profile) == "string" and profile ~= "" then
        tt:AddLine("Profile: " .. profile, 0.62, 0.82, 0.62)
    end

    -- Edit Mode status
    local editActive = false
    local st = _G.MSUF_EditState
    if type(st) == "table" and st.active then
        editActive = true
    end
    if editActive then
        tt:AddLine("Edit Mode: |cff00ff00Active|r", 0.8, 0.8, 0.8)
    end

    tt:AddLine(" ")
    tt:AddLine("|cffffffffLeft Click:|r Open MSUF Menu", 0.7, 0.7, 0.7)
    tt:AddLine("|cffffffffRight Click:|r Toggle Edit Mode", 0.7, 0.7, 0.7)
    tt:Show()
end

function MSUF_AddonCompartment_OnLeave()
    if _G.GameTooltip then
        _G.GameTooltip:Hide()
    end
end
