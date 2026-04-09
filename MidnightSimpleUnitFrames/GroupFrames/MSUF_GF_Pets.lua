--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) MSUF_GF_Pets.lua");
-- MSUF_GF_Pets.lua — Group Frames Pet Support
-- Compact pet health bars below their owner's GF frame.
-- SecureUnitButtonTemplate per pet unit, event-driven updates.
-- Midnight 12.0 secret-safe, zero cost when disabled.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local CreateFrame = CreateFrame
local UnitExists = _G.UnitExists
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local RegisterUnitWatch = _G.RegisterUnitWatch
local UnregisterUnitWatch = _G.UnregisterUnitWatch
local InCombatLockdown = _G.InCombatLockdown
local issecretvalue = _G.issecretvalue

local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS

-- Storage: [ownerFrame] = petFrame
local _petFrames = {}
GF._petFrames = _petFrames

------------------------------------------------------------------------
-- Create a pet frame for a GF owner frame
------------------------------------------------------------------------
local function CreatePetFrame(owner, petUnit)
    Perfy_Trace(Perfy_GetTime(), "Enter", "CreatePetFrame MSUF_GF_Pets.lua:35");
    local f = CreateFrame("Button", nil, owner, "SecureUnitButtonTemplate")
    f:SetAttribute("unit", petUnit)
    f:SetAttribute("type1", "target")
    f.unit = petUnit
    f._msufOwner = owner
    f._msufIsPet = true

    -- Size: proportional to owner (60% width, fixed 14px height)
    local ow = owner:GetWidth()
    f:SetSize(ow * 0.6, 14)

    -- Position: below owner, centered
    f:ClearAllPoints()
    f:SetPoint("TOP", owner, "BOTTOM", 0, -1)

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.85)
    f._bg = bg

    -- Health bar
    local hp = CreateFrame("StatusBar", nil, f)
    hp:SetAllPoints()
    hp:SetStatusBarTexture(TEX_W8)
    hp:SetStatusBarColor(0.2, 0.7, 0.2, 1)
    hp:SetMinMaxValues(0, 1)
    hp:SetValue(1)
    f.health = hp

    -- Border
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = TEX_W8, edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 0.9)
    border:SetFrameLevel(f:GetFrameLevel() + 2)
    f._border = border

    -- Name text (small, centered)
    local name = hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("CENTER", 0, 0)
    name:SetTextColor(1, 1, 1, 0.9)
    name:SetText("")
    f._nameFS = name

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        if self.unit and UnitExists(self.unit) then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Event handler
    f:SetScript("OnEvent", function(self, event, eventUnit)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if eventUnit == self.unit then
                GF._UpdatePetHealth(self)
            end
        elseif event == "UNIT_NAME_UPDATE" then
            if eventUnit == self.unit then
                GF._UpdatePetName(self)
            end
        elseif event == "UNIT_PET" then
            -- Owner's pet changed — refresh visibility
            GF._RefreshPetVisibility(self)
        end
    end)

    -- Register per-unit events
    local ownerUnit = petUnit:gsub("pet", "")
    if ownerUnit == "" then ownerUnit = "player" end
    f._ownerUnit = ownerUnit

    f:RegisterUnitEvent("UNIT_HEALTH", petUnit)
    f:RegisterUnitEvent("UNIT_MAXHEALTH", petUnit)
    f:RegisterUnitEvent("UNIT_NAME_UPDATE", petUnit)
    f:RegisterUnitEvent("UNIT_PET", ownerUnit)

    -- Secure visibility: auto show/hide based on unit existence
    RegisterUnitWatch(f)

    f:Hide()  -- starts hidden, RegisterUnitWatch manages visibility
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreatePetFrame MSUF_GF_Pets.lua:35");
    return f
end

------------------------------------------------------------------------
-- Update pet health (secret-safe: raw values → C-side SetValue)
------------------------------------------------------------------------
function GF._UpdatePetHealth(f)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF._UpdatePetHealth MSUF_GF_Pets.lua:128");
    if not f or not f.unit then return end
    if not UnitExists(f.unit) then return end
    local hp = UnitHealth(f.unit)
    local hpMax = UnitHealthMax(f.unit)
    f.health:SetMinMaxValues(0, hpMax)
    f.health:SetValue(hp)

    -- Color by owner class (if available)
    local owner = f._msufOwner
    if owner and owner._msufGFClass then
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[owner._msufGFClass]
        if cc then
            f.health:SetStatusBarColor(cc.r * 0.7, cc.g * 0.7, cc.b * 0.7, 1)
            Perfy_Trace(Perfy_GetTime(), "Leave", "GF._UpdatePetHealth MSUF_GF_Pets.lua:128");
            return
        end
    end
    -- Fallback: desaturated green
    f.health:SetStatusBarColor(0.2, 0.55, 0.2, 1)
Perfy_Trace(Perfy_GetTime(), "Leave", "GF._UpdatePetHealth MSUF_GF_Pets.lua:128");
end

------------------------------------------------------------------------
-- Update pet name
------------------------------------------------------------------------
function GF._UpdatePetName(f)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF._UpdatePetName MSUF_GF_Pets.lua:152");
    if not f or not f.unit or not f._nameFS then return end
    local name = UnitExists(f.unit) and UnitName(f.unit) or ""
    if name and #name > 8 then name = name:sub(1, 8) end
    f._nameFS:SetText(name or "")
Perfy_Trace(Perfy_GetTime(), "Leave", "GF._UpdatePetName MSUF_GF_Pets.lua:152");
end

------------------------------------------------------------------------
-- Refresh pet visibility (called on UNIT_PET / owner change)
------------------------------------------------------------------------
function GF._RefreshPetVisibility(f)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF._RefreshPetVisibility MSUF_GF_Pets.lua:162");
    if not f or not f.unit then return end
    -- RegisterUnitWatch handles show/hide automatically
    -- Just update visuals if visible
    if f:IsShown() and UnitExists(f.unit) then
        GF._UpdatePetHealth(f)
        GF._UpdatePetName(f)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF._RefreshPetVisibility MSUF_GF_Pets.lua:162");
end

------------------------------------------------------------------------
-- Resolve pet unit token from owner GF frame
------------------------------------------------------------------------
local function GetPetUnit(ownerFrame)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GetPetUnit MSUF_GF_Pets.lua:175");
    local unit = ownerFrame and ownerFrame.unit
    if not unit then return nil end
    -- party1 → partypet1, player → pet, raid5 → raidpet5
    if unit == "player" then return "pet" end
    local partyIdx = unit:match("^party(%d)$")
    if partyIdx then return "partypet" .. partyIdx end
    local raidIdx = unit:match("^raid(%d+)$")
    if raidIdx then return "raidpet" .. raidIdx end
    Perfy_Trace(Perfy_GetTime(), "Leave", "GetPetUnit MSUF_GF_Pets.lua:175");
    return nil
end

------------------------------------------------------------------------
-- Attach pet frame to a GF owner frame (called from RegisterUnitEvents)
------------------------------------------------------------------------
function GF.AttachPetFrame(ownerFrame)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.AttachPetFrame MSUF_GF_Pets.lua:190");
    if not ownerFrame then return end
    local kind = ownerFrame._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if not conf or conf.showPets == false then return end

    local petUnit = GetPetUnit(ownerFrame)
    if not petUnit then return end

    -- Reuse existing pet frame or create new
    local pf = _petFrames[ownerFrame]
    if pf then
        -- Update unit if changed (frame reused for different unit)
        if pf.unit ~= petUnit and not InCombatLockdown() then
            UnregisterUnitWatch(pf)
            pf:SetAttribute("unit", petUnit)
            pf.unit = petUnit
            pf:RegisterUnitEvent("UNIT_HEALTH", petUnit)
            pf:RegisterUnitEvent("UNIT_MAXHEALTH", petUnit)
            pf:RegisterUnitEvent("UNIT_NAME_UPDATE", petUnit)
            local ownerUnit = petUnit:gsub("pet", "")
            if ownerUnit == "" then ownerUnit = "player" end
            pf._ownerUnit = ownerUnit
            pf:RegisterUnitEvent("UNIT_PET", ownerUnit)
            RegisterUnitWatch(pf)
        end
    else
        if InCombatLockdown() then return end  -- can't create secure frames in combat
        pf = CreatePetFrame(ownerFrame, petUnit)
        _petFrames[ownerFrame] = pf
    end

    -- Sync size with owner
    local ow = ownerFrame:GetWidth()
    pf:SetSize(ow * 0.6, 14)

    -- Apply bar texture from config
    local barTex = conf.barTexture
    if barTex and type(barTex) == "string" then
        local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local path = LSM:Fetch("statusbar", barTex)
            if path then pf.health:SetStatusBarTexture(path) end
        end
    end

    -- Initial update
    if UnitExists(petUnit) then
        GF._UpdatePetHealth(pf)
        GF._UpdatePetName(pf)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF.AttachPetFrame MSUF_GF_Pets.lua:190");
end

------------------------------------------------------------------------
-- Detach pet frame from owner (called from UnregisterUnitEvents)
------------------------------------------------------------------------
function GF.DetachPetFrame(ownerFrame)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.DetachPetFrame MSUF_GF_Pets.lua:246");
    if not ownerFrame then return end
    local pf = _petFrames[ownerFrame]
    if not pf then return end
    if not InCombatLockdown() then
        UnregisterUnitWatch(pf)
        pf:Hide()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF.DetachPetFrame MSUF_GF_Pets.lua:246");
end

------------------------------------------------------------------------
-- Show/hide all pet frames (called on config change)
------------------------------------------------------------------------
function GF.RefreshAllPets()
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.RefreshAllPets MSUF_GF_Pets.lua:259");
    for owner, pf in pairs(_petFrames) do
        local kind = owner._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        if conf and conf.showPets ~= false and owner.unit then
            GF.AttachPetFrame(owner)
        else
            GF.DetachPetFrame(owner)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF.RefreshAllPets MSUF_GF_Pets.lua:259");
end

function GF.HideAllPets()
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.HideAllPets MSUF_GF_Pets.lua:271");
    if InCombatLockdown() then return end
    for _, pf in pairs(_petFrames) do
        UnregisterUnitWatch(pf)
        pf:Hide()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF.HideAllPets MSUF_GF_Pets.lua:271");
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) MSUF_GF_Pets.lua");