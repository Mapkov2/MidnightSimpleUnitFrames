-- MidnightSimpleUnitFrames_MinimapButton.lua
-- Minimal, robust minimap icon implementation (LibDataBroker + LibDBIcon, with safe fallback).

local addonName, addonNS = ...
local ns = (_G and _G.MSUF_NS) or addonNS or {}
if _G then _G.MSUF_NS = ns end

local _G = _G

local ICON_PATH = "Interface/AddOns/" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "/Media/MSUF_MinimapIcon.tga"

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function EnsureGeneralDB()
    if type(_G.MSUF_DB) ~= "table" then return nil end
    local db = _G.MSUF_DB
    if type(db.general) ~= "table" then
        db.general = {}
    end
    local g = db.general
    if g.showMinimapIcon == nil then
        g.showMinimapIcon = true
    end
    if type(g.minimapIconDB) ~= "table" then
        g.minimapIconDB = { minimapPos = 220, hide = not g.showMinimapIcon }
    else
        if g.minimapIconDB.minimapPos == nil then g.minimapIconDB.minimapPos = 220 end
        if g.minimapIconDB.hide == nil then g.minimapIconDB.hide = not g.showMinimapIcon end
    end
    return g
end

local function ToggleEditMode()
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        local st = _G.MSUF_EditState
        local nextActive = true
        if type(st) == "table" and st.active ~= nil then
            nextActive = not st.active
        end
        pcall(_G.MSUF_SetMSUFEditModeDirect, nextActive, nil)
        return
    end
    if type(_G.MSUF_ToggleEditMode) == "function" then
        pcall(_G.MSUF_ToggleEditMode)
        return
    end
    if type(_G.MSUF_EditMode_Toggle) == "function" then
        pcall(_G.MSUF_EditMode_Toggle)
        return
    end
end

local function ToggleOptionsWindow()
    if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        pcall(_G.MSUF_OpenStandaloneOptionsWindow, "home")
        return
    end
    if type(_G.MSUF_ShowStandaloneOptionsWindow) == "function" then
        pcall(_G.MSUF_ShowStandaloneOptionsWindow, "home")
        return
    end
    -- Fallback: try to open Blizzard settings (if present)
    if _G.Settings and type(_G.Settings.OpenToCategory) == "function" then
        pcall(_G.Settings.OpenToCategory, addonName)
    elseif type(_G.InterfaceOptionsFrame_OpenToCategory) == "function" then
        pcall(_G.InterfaceOptionsFrame_OpenToCategory, addonName)
    end
end

local function BuildTooltip(tt)
    if not tt then return end
    if not tt.AddLine then return end

    tt:AddLine("Midnight Simple Unit Frames", 1, 1, 1)

    -- Version
    local version = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
        and _G.C_AddOns.GetAddOnMetadata(addonName, "Version")
    if type(version) == "string" and version ~= "" then
        tt:AddLine("v" .. version, 0.6, 0.6, 0.6)
    end

    tt:AddLine(" ")

    -- Active profile
    local profile = _G.MSUF_ActiveProfile
    if type(profile) == "string" and profile ~= "" then
        tt:AddLine("Profile: " .. profile, 0.62, 0.82, 0.62)
    end

    -- Edit Mode status
    local st = _G.MSUF_EditState
    if type(st) == "table" and st.active then
        tt:AddLine("Edit Mode: |cff00ff00Active|r", 0.8, 0.8, 0.8)
    end

    tt:AddLine(" ")
    tt:AddLine("|cffffffffLeft Click:|r Open MSUF", 0.7, 0.7, 0.7)
    tt:AddLine("|cffffffffRight Click:|r Toggle Edit Mode", 0.7, 0.7, 0.7)
    tt:AddLine("|cffffffffShift + Click:|r Open Profiles", 0.7, 0.7, 0.7)
end

-- LDB/DBIcon path
local LibStub = _G and _G.LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true) or nil
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true) or nil

local DATA_NAME = "MidnightSimpleUnitFrames"
local dataObj = nil
local usingLDB = false

-- Fallback button path
local fallbackBtn = nil

local function ApplyShowHide(enabled)
    enabled = not not enabled

    if usingLDB and DBIcon and type(DBIcon.Show) == "function" and type(DBIcon.Hide) == "function" then
        if enabled then
            pcall(DBIcon.Show, DBIcon, DATA_NAME)
        else
            pcall(DBIcon.Hide, DBIcon, DATA_NAME)
        end
        return
    end

    if fallbackBtn then
        if enabled then fallbackBtn:Show() else fallbackBtn:Hide() end
    end
end

local function EnsureInitialized()
    local g = EnsureGeneralDB()
    if not g then return false end

    -- Prefer LibDBIcon if present
    if LDB and DBIcon then
        if not dataObj then
            -- Use a stable stock icon so this never breaks if a custom path is missing.
            dataObj = LDB:NewDataObject(DATA_NAME, {
                type = "data source",
                text = "MSUF",
                icon = ICON_PATH,
                OnClick = function(_, button)
                    if button == "RightButton" then
                        ToggleEditMode()
                    elseif IsShiftKeyDown() then
                        if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
                            pcall(_G.MSUF_OpenStandaloneOptionsWindow, "profiles")
                        end
                    else
                        ToggleOptionsWindow()
                    end
                end,
                OnTooltipShow = function(tt)
                    BuildTooltip(tt)
                end,
            })
        end

        -- Register once (idempotent)
        if type(DBIcon.IsRegistered) == "function" then
            local ok, reg = pcall(DBIcon.IsRegistered, DBIcon, DATA_NAME)
            if not ok or not reg then
                pcall(DBIcon.Register, DBIcon, DATA_NAME, dataObj, g.minimapIconDB)
            end
        else
            pcall(DBIcon.Register, DBIcon, DATA_NAME, dataObj, g.minimapIconDB)
        end

        usingLDB = true
        ApplyShowHide(not g.minimapIconDB.hide)
        return true
    end

    -- Fallback: simple minimap-attached button
    if not fallbackBtn and _G.Minimap and type(_G.CreateFrame) == "function" then
        local b = CreateFrame("Button", "MSUF_MinimapButton", _G.Minimap)
        b:SetSize(32, 32)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(8)

        b:SetNormalTexture("Interface/Minimap/UI-Minimap-Background")
        b:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER")
        icon:SetSize(18, 18)
        icon:SetTexture(ICON_PATH)
        b._msufIcon = icon

        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                ToggleEditMode()
            elseif IsShiftKeyDown() then
                if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
                    pcall(_G.MSUF_OpenStandaloneOptionsWindow, "profiles")
                end
            else
                ToggleOptionsWindow()
            end
        end)

        b:SetScript("OnEnter", function(self)
            if _G.GameTooltip then
                _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                BuildTooltip(_G.GameTooltip)
                _G.GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)

        -- Position by minimapPos degrees (same semantics as LibDBIcon)
        local function Repos()
            local gg = EnsureGeneralDB()
            local pos = (gg and gg.minimapIconDB and tonumber(gg.minimapIconDB.minimapPos)) or 220
            local r = 80
            local rad = math.rad(pos)
            local x = math.cos(rad) * r
            local y = math.sin(rad) * r
            b:ClearAllPoints()
            b:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
        end

        b:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local gg = EnsureGeneralDB()
                if not gg then return end
                local mx, my = GetCursorPosition()
                local scale = _G.Minimap:GetEffectiveScale() or 1
                mx, my = mx / scale, my / scale
                local cx, cy = _G.Minimap:GetCenter()
                local dx, dy = mx - cx, my - cy
                local angle = math.deg(atan2(dy, dx))
                -- Convert to LibDBIcon-style degrees (0 on right)
                gg.minimapIconDB.minimapPos = angle
                Repos()
            end)
        end)
        b:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        b:RegisterForDrag("LeftButton")

        fallbackBtn = b
        Repos()
    end

    usingLDB = false
    ApplyShowHide(g.showMinimapIcon)
    return true
end

-- Public API used by Options_Misc.lua
function _G.MSUF_SetMinimapIconEnabled(enabled)
    local g = EnsureGeneralDB()
    if not g then return end

    enabled = not not enabled
    g.showMinimapIcon = enabled
    if type(g.minimapIconDB) ~= "table" then g.minimapIconDB = { minimapPos = 220 } end
    g.minimapIconDB.hide = not enabled

    EnsureInitialized()
    ApplyShowHide(enabled)
end

-- Init on login (DB is expected to exist by then)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local g = EnsureGeneralDB()
    if g then
        EnsureInitialized()
        ApplyShowHide(g.showMinimapIcon)
    end
end)
