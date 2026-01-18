-- MSUF_CooldownManagerIcons.lua
-- Embedded version of CooldownManagerIcons as an MSUF module.
-- Converts cooldown manager bars (BuffBarCooldownViewer) into icons,
-- driven by MSUF_DB.gameplay.cooldownIcons and the Gameplay options toggle.

local addonName, ns = ...

local CreateFrame = CreateFrame
local ipairs = ipairs
local type = type

local Masque
local MasqueGroup

-- SavedVars shim: reuse MSUF_DB.gameplay
local function EnsureCDConfig()
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if type(MSUF_DB.gameplay) ~= "table" then
        MSUF_DB.gameplay = {}
    end

    local g = MSUF_DB.gameplay
    if g.cooldownIcons == nil then
        g.cooldownIcons = true
    end
    return g
end

local function IsIconModeEnabled()
    local g = EnsureCDConfig()
    return g.cooldownIcons and true or false
end

-- Container-Frame aus /fstack
local VIEWER_FRAME_NAME = "BuffBarCooldownViewer"

local ICON_SIZE       = 32
local ICON_SPACING    = 4
-- We do not need ultra-fast ticks here; icon layout only changes when entries appear/disappear.
-- Keep this modest to reduce allocations and anchor churn.
local UPDATE_INTERVAL = 0.10

local viewer

-- Forward declaration (TryInitViewer hooks call this before its definition).
local MSUF_CDIcons_UpdateOnUpdateState

local elapsedSinceUpdate = 0

-------------------------------------------------------
-- Duration-Text vom Balken aufs Icon umhängen
-------------------------------------------------------
local function MoveDurationToIcon(entry, iconFrame, bar)
    local duration = bar and bar.Duration
    if not duration or entry._cmiDurationMoved then
        return
    end

    -- Original-Parent & Punkte merken
    entry._cmiDurationMoved      = true
    entry._cmiDurationOrigParent = duration:GetParent()
    entry._cmiDurationOrigPoints = {}

    for i = 1, duration:GetNumPoints() do
        local point, rel, relPoint, x, y = duration:GetPoint(i)
        entry._cmiDurationOrigPoints[i] = {
            point = point, rel = rel, relPoint = relPoint, x = x, y = y,
        }
    end

    duration:SetParent(iconFrame)
    duration:ClearAllPoints()
    duration:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)

    local font, size, flags = duration:GetFont()
    duration:SetFont(font, (size or 12) + 2, flags)
    duration:SetJustifyH("CENTER")
    duration:SetJustifyV("MIDDLE")
    duration:SetDrawLayer("OVERLAY")
end

local function RestoreDuration(entry)
    if not entry._cmiDurationMoved then return end

    local bar = entry.Bar
    if not bar or not bar.Duration then return end

    local duration   = bar.Duration
    local origParent = entry._cmiDurationOrigParent
    local origPoints = entry._cmiDurationOrigPoints

    if origParent and origPoints then
        duration:SetParent(origParent)
        duration:ClearAllPoints()
        for _, p in ipairs(origPoints) do
            duration:SetPoint(p.point, p.rel, p.relPoint, p.x, p.y)
        end
    end

    entry._cmiDurationMoved      = nil
    entry._cmiDurationOrigParent = nil
    entry._cmiDurationOrigPoints = nil
end

local function ResetEntryToBar(entry)
    if not entry then return end

    local bar = entry.Bar
    if bar then
        bar:SetAlpha(1)
        bar:Show()
    end

    RestoreDuration(entry)

    entry._cmiBarHidden   = nil
    entry._cmiIconApplied = nil
    entry._cmiIconIndex   = nil
end

-------------------------------------------------------
-- Bars → Icons (mit optionalem Masque-Skin)
-------------------------------------------------------
local function ApplyIconLayout()
    if not viewer or not IsIconModeEnabled() then return end

    local index = 0
    local masqueDirty = false

    -- NOTE: This table allocation is now cheap because we tick slowly and only re-anchor when needed.
    local children = { viewer:GetChildren() }
    for i = 1, #children do
        local entry = children[i]
        local iconFrame = entry and entry.Icon    -- Frame mit Texture
        local bar       = entry and entry.Bar     -- StatusBar der Tracked Bar

        if iconFrame and bar and entry:IsShown() then
            index = index + 1

            -- Bar unsichtbar machen, aber intern weiterlaufen lassen (nur 1x pro Entry).
            if not entry._cmiBarHidden then
                bar:SetAlpha(0)
                entry._cmiBarHidden = true
            end

            local needsAnchor = (entry._cmiIconIndex ~= index) or (not entry._cmiIconApplied)
            if needsAnchor then
                local icon = iconFrame.Icon or iconFrame

                -- Entry als Icon-Container benutzen
                entry:ClearAllPoints()
                entry:SetSize(ICON_SIZE, ICON_SIZE)
                entry:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", 0, -(index - 1) * (ICON_SIZE + ICON_SPACING))

                -- IconFrame an Entry anpassen
                iconFrame:ClearAllPoints()
                iconFrame:SetAllPoints(entry)
                iconFrame:SetSize(ICON_SIZE, ICON_SIZE)

                if icon and icon.SetAllPoints then
                    icon:ClearAllPoints()
                    icon:SetAllPoints(iconFrame)
                end
                if icon and icon.SetTexCoord then
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end

                entry._cmiIconIndex   = index
                entry._cmiIconApplied = true
            end

            -- Masque-Skinning des Icon-Frames (einmalig)
            if MasqueGroup and not iconFrame._cmiMasqueSkinned then
                local icon = iconFrame.Icon or iconFrame
                MasqueGroup:AddButton(iconFrame, {
                    Icon = icon,
                })
                iconFrame._cmiMasqueSkinned = true
                masqueDirty = true
            end

            -- Blizzard-Duration-Text aufs Icon (einmalig)
            MoveDurationToIcon(entry, iconFrame, bar)
        end
    end

    if MasqueGroup and masqueDirty then
        MasqueGroup:ReSkin()
    end
end

-------------------------------------------------------
-- Viewer suchen
-------------------------------------------------------
local function TryInitViewer()
    if viewer then return true end
    local frame = _G[VIEWER_FRAME_NAME]
    if not frame then return false end

    viewer = frame

    -- Idle perf: only run our OnUpdate loop while the viewer is actually visible.
    if viewer and not viewer.__MSUF_CDIcons_Hooked then
        viewer.__MSUF_CDIcons_Hooked = true
        viewer:HookScript("OnShow", function()
            if MSUF_CDIcons_UpdateOnUpdateState then
                MSUF_CDIcons_UpdateOnUpdateState()
            end
        end)
        viewer:HookScript("OnHide", function()
            if MSUF_CDIcons_UpdateOnUpdateState then
                MSUF_CDIcons_UpdateOnUpdateState()
            end
        end)
    end
    return true
end

-------------------------------------------------------
-- OnUpdate: Layout regelmäßig anwenden
-------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Masque erst jetzt holen, wenn es wirklich geladen ist
        if LibStub then
            Masque = LibStub("Masque", true)
            if Masque then
                MasqueGroup = Masque:Group("Cooldown Manager Icons", "Tracked Bars")
            end
        end
        TryInitViewer()
        if MSUF_CDIcons_UpdateOnUpdateState then
            MSUF_CDIcons_UpdateOnUpdateState()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Some UIs create the viewer later; try again once we're in the world.
        TryInitViewer()
        if MSUF_CDIcons_UpdateOnUpdateState then
            MSUF_CDIcons_UpdateOnUpdateState()
        end
    end
end)

local function MSUF_CDIcons_OnUpdate(self, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + (elapsed or 0)
    if elapsedSinceUpdate < UPDATE_INTERVAL then
        return
    end
    elapsedSinceUpdate = 0

    if not IsIconModeEnabled() then
        -- Safety: should normally be disabled via UpdateOnUpdateState, but avoid doing work anyway.
        return
    end

    if not viewer then
        TryInitViewer()
    end

    if viewer and viewer:IsShown() then
        ApplyIconLayout()
    end
end

MSUF_CDIcons_UpdateOnUpdateState = function()
    EnsureCDConfig()

    -- Make sure the viewer reference is resolved (if possible).
    TryInitViewer()

    -- Off means Off: only run our OnUpdate loop when the feature is enabled, and when the viewer is visible.
    -- If the viewer is not created yet, we keep a lightweight ticker running to discover it.
    local enabled = IsIconModeEnabled()
    local shouldRun = enabled and ((not viewer) or viewer:IsShown())

    if not shouldRun then
        if f:GetScript("OnUpdate") then
            f:SetScript("OnUpdate", nil)
        end
        elapsedSinceUpdate = 0
        return
    end

    if not f:GetScript("OnUpdate") then
        elapsedSinceUpdate = 0
        f:SetScript("OnUpdate", MSUF_CDIcons_OnUpdate)
    end
end

-- Initialize ticker state (in case icon mode is already enabled at login).
MSUF_CDIcons_UpdateOnUpdateState()


-- Helper callable from Gameplay options: applies the current icon mode
function MSUF_ApplyCooldownIconMode()
    EnsureCDConfig()

    if not viewer then
        if not TryInitViewer() then
            -- Viewer not ready yet; keep the ticker alive so we can apply once it exists.
            if MSUF_CDIcons_UpdateOnUpdateState then
                MSUF_CDIcons_UpdateOnUpdateState()
            end
            return
        end
    end
    if not viewer then
        return
    end

    if not IsIconModeEnabled() then
        -- Bars & Duration zurücksetzen
        for _, entry in ipairs({ viewer:GetChildren() }) do
            ResetEntryToBar(entry)
        end
    else
        ApplyIconLayout()
    end

    -- Keep the ticker state in sync with the toggle.
    if MSUF_CDIcons_UpdateOnUpdateState then
        MSUF_CDIcons_UpdateOnUpdateState()
    end
end

-------------------------------------------------------
-- Slashcommand: /cmi  → IconMode an/aus
-------------------------------------------------------
SLASH_CMI1 = "/cmi"
SlashCmdList.CMI = function()
    local g = EnsureCDConfig()
    g.cooldownIcons = not g.cooldownIcons
    print("MSUF: Cooldown icon mode: " .. (g.cooldownIcons and "ON" or "OFF"))

    if not viewer then
        TryInitViewer()
    end

    if viewer then
        if not IsIconModeEnabled() then
            for _, entry in ipairs({ viewer:GetChildren() }) do
                ResetEntryToBar(entry)
            end
        else
            ApplyIconLayout()
        end
    end

    if MSUF_CDIcons_UpdateOnUpdateState then
        MSUF_CDIcons_UpdateOnUpdateState()
    end
end
