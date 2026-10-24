--- MidnightSimpleUnitFrames_MinimapButton.lua
--- Minimal, robust minimap icon implementation (LibDataBroker + LibDBIcon, with safe fallback).

local addonName, addonNS = ...
local MSUF = addonNS
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/MSUF_MinimapButton.lua")

local _G = _G
local ExportPublic = MSUF.ExportPublic

local ICON_PATH = "Interface/AddOns/" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "/Media/MSUF_MinimapIcon.tga"

local atan2 = math.atan2

local Tr = MSUF.Translate

local function EnsureGeneralDB()
    local db = MSUF_DB
    if type(db) ~= "table" then return nil end
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
    local st = MSUF.Optional("MSUF_EditState")
    local nextActive = true
    if st and st.active ~= nil then
        nextActive = not st.active
    end
    MSUF.Require("MSUF_SetMSUFEditModeDirect", "Shell/MSUF_MinimapButton.lua")(nextActive, nil)
end

local function ToggleOptionsWindow()
    local openStandalone = MSUF.Optional("MSUF_OpenStandaloneOptionsWindow")
    if type(openStandalone) == "function" then
        openStandalone()
        return
    end
    -- Kernel/MSUF_OptionsLoader.lua forwards this entry point until the menu loads.
    MSUF.Require("MSUF_ShowStandaloneOptionsWindow", "Shell/MSUF_MinimapButton.lua")()
end

local function BuildTooltip(tt, owner, opts)
    if not tt then return end
    if not tt.AddLine then return end
    opts = opts or {}
    if owner and tt.SetOwner then tt:SetOwner(owner, opts.anchor or "ANCHOR_LEFT") end

    tt:AddLine("Midnight Simple Unit Frames", 1, 1, 1)

    --- Version, from the one shared accessor in Game/Shared/Initialize.lua: it
    --- is resolved once from the TOC this client loaded, never asked again.
    local getVersion = MSUF.GetAddonVersion
    local version = getVersion()
    if type(version) == "string" and version ~= "" then
        local displayVersion = opts.versionLabel and (Tr("Version:") .. " " .. version) or (version:match("^%d") and ("v" .. version) or version)
        tt:AddLine(displayVersion, 0.6, 0.6, 0.6)
    end

    if opts.blankAfterVersion ~= false then tt:AddLine(" ") end

    --- Active profile
    local profile = MSUF_ActiveProfile
    if type(profile) == "string" and profile ~= "" then
        tt:AddLine(Tr("Profile:") .. " " .. profile, 0.62, 0.82, 0.62)
    end

    --- Edit Mode status
    local st = MSUF.Optional("MSUF_EditState")
    if st and st.active then
        tt:AddLine(Tr("Edit Mode: |cff00ff00Active|r"), 0.8, 0.8, 0.8)
    end

    tt:AddLine(" ")
    tt:AddLine(Tr(opts.leftText or "|cffffffffLeft Click:|r Open MSUF"), 0.7, 0.7, 0.7)
    tt:AddLine(Tr(opts.rightText or "|cffffffffRight Click:|r Toggle Edit Mode"), 0.7, 0.7, 0.7)
    if opts.shiftText ~= false then tt:AddLine(Tr(opts.shiftText or "|cffffffffShift + Click:|r Open Profiles"), 0.7, 0.7, 0.7) end
    if opts.show and tt.Show then tt:Show() end
end

MSUF.MinimapButton = MSUF.MinimapButton or {}
MSUF.MinimapButton.Tr = Tr
MSUF.MinimapButton.ToggleEditMode = ToggleEditMode
MSUF.MinimapButton.ToggleOptionsWindow = ToggleOptionsWindow
MSUF.MinimapButton.BuildTooltip = BuildTooltip

--- LDB/DBIcon path
local LibStub = LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true) or nil
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true) or nil

local DATA_NAME = "MidnightSimpleUnitFrames"
local dataObj = nil
local usingLDB = false
local loginReady = false

--- Fallback button path
local fallbackBtn = nil
local fallbackRepos = nil

local function ApplyShowHide(enabled)
    enabled = not not enabled

    if usingLDB and DBIcon and type(DBIcon.Show) == "function" and type(DBIcon.Hide) == "function" then
        if enabled then
            DBIcon:Show(DATA_NAME)
        else
            DBIcon:Hide(DATA_NAME)
        end
        return
    end

    if fallbackBtn then
        if enabled then fallbackBtn:Show() else fallbackBtn:Hide() end
    end
end

local HandleMinimapClick = function(_, button)
if button == "RightButton" then
                ToggleEditMode()
            elseif IsShiftKeyDown() then
                local openStandalone = MSUF.Optional("MSUF_OpenStandaloneOptionsWindow")
                if type(openStandalone) == "function" then
                    openStandalone("profiles")
                end
            else
                ToggleOptionsWindow()
            end
end

local function EnsureInitialized()
    if not loginReady then return false end
    local root = MSUF_GlobalDB
    local profiles = root and root.profiles
    if not profiles or profiles[MSUF_ActiveProfile] ~= MSUF_DB then return false end
    local g = EnsureGeneralDB()
    if not g or (not g.showMinimapIcon and not usingLDB and not fallbackBtn) then return false end

    --- Prefer LibDBIcon if present
    if LDB and DBIcon then
        if not dataObj then
            --- Use a stable stock icon so this never breaks if a custom path is missing.
            dataObj = LDB:NewDataObject(DATA_NAME, {
                type = "data source",
                text = "MSUF",
                icon = ICON_PATH,
                OnClick = HandleMinimapClick,
                OnTooltipShow = function(tt)
                    BuildTooltip(tt)
                end,
            })
        end

        --- Register once (idempotent)
        if type(DBIcon.IsRegistered) == "function" then
            if not DBIcon:IsRegistered(DATA_NAME) then
                DBIcon:Register(DATA_NAME, dataObj, g.minimapIconDB)
            end
        else
            DBIcon:Register(DATA_NAME, dataObj, g.minimapIconDB)
        end

        -- Refresh replaces LibDBIcon's stored DB reference after a bind.
        DBIcon:Refresh(DATA_NAME, g.minimapIconDB)
        usingLDB = true
        ApplyShowHide(not g.minimapIconDB.hide)
        return true
    end

    --- Fallback: simple minimap-attached button
    if not fallbackBtn and Minimap and type(CreateFrame) == "function" then
        local b = PixelLayoutRegion(CreateFrame("Button", "MSUF_MinimapButton", Minimap))
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetSize(32, 32)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(8)

        PixelLayoutRegion(b, "SetNormalTexture", "Interface/Minimap/UI-Minimap-Background")
        PixelLayoutRegion(b, "SetHighlightTexture", "Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

        local icon = PixelLayoutRegion(b:CreateTexture(nil, "ARTWORK"))
        icon:SetPoint("CENTER")
        icon:SetSize(18, 18)
        icon:SetTexture(ICON_PATH)
        b._msufIcon = icon

        b:SetScript("OnClick", HandleMinimapClick)

        b:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                BuildTooltip(GameTooltip)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        --- Position by minimapPos degrees (same semantics as LibDBIcon)
        local function Repos()
            local gg = EnsureGeneralDB()
            local pos = (gg and gg.minimapIconDB and tonumber(gg.minimapIconDB.minimapPos)) or 220
            local r = 80
            local rad = math.rad(pos)
            local x = math.cos(rad) * r
            local y = math.sin(rad) * r
            b:ClearAllPoints()
            b:SetPoint("CENTER", Minimap, "CENTER", x, y)
        end
        fallbackRepos = Repos

        b:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local gg = EnsureGeneralDB()
                if not gg then return end
                local mx, my = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale() or 1
                mx, my = mx / scale, my / scale
                local cx, cy = Minimap:GetCenter()
                local dx, dy = mx - cx, my - cy
                local angle = math.deg(atan2(dy, dx))
                --- Convert to LibDBIcon-style degrees (0 on right)
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

function MSUF.MinimapButton.RefreshProfileBinding()
    if EnsureInitialized() and fallbackRepos then fallbackRepos() end
end

--- Public API used by Options_Misc.lua
local function MSUF_SetMinimapIconEnabled(enabled)
    local g = EnsureGeneralDB()
    if not g then return end

    enabled = not not enabled
    g.showMinimapIcon = enabled
    if type(g.minimapIconDB) ~= "table" then g.minimapIconDB = { minimapPos = 220 } end
    g.minimapIconDB.hide = not enabled

    if enabled then
        EnsureInitialized()
        ApplyShowHide(true)
    elseif dataObj or fallbackBtn or usingLDB then
        ApplyShowHide(false)
    end
end
ExportPublic("MSUF_SetMinimapIconEnabled", MSUF_SetMinimapIconEnabled)

local function MSUF_SetMinimapIconPosition(value)
    local g = EnsureGeneralDB()
    if not g then return false end
    g.minimapIconDB = type(g.minimapIconDB) == "table" and g.minimapIconDB or {}
    value = tonumber(value) or 220
    if value < 0 then value = 0 elseif value > 360 then value = 360 end
    g.minimapIconDB.minimapPos = value
    if usingLDB and DBIcon and type(DBIcon.Refresh) == "function" then
        DBIcon:Refresh(DATA_NAME, g.minimapIconDB)
    elseif fallbackRepos then
        fallbackRepos()
    end
    return true
end
ExportPublic("MSUF_SetMinimapIconPosition", MSUF_SetMinimapIconPosition)

--- Init on login. The saved setting is read there, never while this file
--- loads: the client loads the SavedVariables after every file ran.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    loginReady = true
    self:UnregisterEvent("PLAYER_LOGIN")
    self:SetScript("OnEvent", nil)
    local g = EnsureGeneralDB()
    if g then
        if g.showMinimapIcon then
            EnsureInitialized()
            ApplyShowHide(true)
        end
    end
end)
