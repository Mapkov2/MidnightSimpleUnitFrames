--- Vanilla/TBC Hunter Pet Happiness indicator.
---
--- Loaded only by the Vanilla and TBC unit-frame manifests. Cataclysm 4.1
--- removed Happiness/Loyalty; Mists and Mainline therefore never parse this
--- file, register its events, or create its texture.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local UF = MSUF.UF
if not (UF and type(UF.RegisterElement) == "function") then return end

local CreateFrame = _G.CreateFrame
local GetPetHappiness = _G.GetPetHappiness
local HasPetUI = _G.HasPetUI
local tonumber = tonumber
local type = type
local floor = math.floor

local EMPTY_EVENTS = {}
-- UNIT_PET carries "player" for the player's pet and can use the UF core's
-- exact dependent-unit route. UNIT_HAPPINESS has no unit payload in Classic,
-- so it must remain on the unitless side just like Blizzard's PetFrame.
local HAPPINESS_EVENTS = { "UNIT_PET" }
local HAPPINESS_LIFECYCLE_EVENTS = { "UNIT_HAPPINESS", "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" }
local TEXTURE = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local TEX_COORDS = {
    [1] = { 0.375, 0.5625, 0, 0.359375 }, -- Unhappy: 75% damage
    [2] = { 0.1875, 0.375, 0, 0.359375 }, -- Content: 100% damage
    [3] = { 0, 0.1875, 0, 0.359375 },     -- Happy: 125% damage
}

local Happiness = { UpdateOnApply = true }

local function Config(frame, spec)
    spec = spec or (frame and frame.MSUFSpec)
    return spec and spec.status and spec.status.petHappiness or nil
end

local function ClampLayer(value)
    value = floor((tonumber(value) or 7) + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end

local function EnsureHolder(frame, layer)
    if not (frame and CreateFrame) then return nil end
    local holder = frame.petHappinessIndicatorHolder
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        if holder.EnableMouse then holder:EnableMouse(false) end
        if holder.SetClipsChildren then holder:SetClipsChildren(false) end
        frame.petHappinessIndicatorHolder = holder
    end

    layer = ClampLayer(layer)
    if holder.SetFrameLevel then
        local layers = UF.Layers or {}
        local base = frame.Health or frame.hpBar or frame
        local level = layers.StatusLevel and layers.StatusLevel(frame, layer, 7)
            or (((base.GetFrameLevel and base:GetFrameLevel()) or 0) + 10 + layer)
        if holder._msufHappinessFrameLevel ~= level then
            holder:SetFrameLevel(level)
            holder._msufHappinessFrameLevel = level
        end
    end
    return holder
end

local function EnsureTexture(frame, cfg)
    local holder = EnsureHolder(frame, cfg and cfg.layer)
    if not holder then return nil end
    local tex = frame.petHappinessIndicatorIcon
    if not tex then
        tex = holder:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(TEXTURE)
        tex:Hide()
        frame.petHappinessIndicatorIcon = tex
    elseif tex.GetParent and tex:GetParent() ~= holder and tex.SetParent then
        tex:SetParent(holder)
    end
    return tex
end

local function Layout(frame, tex, cfg, status)
    if not (frame and tex and cfg) then return end
    EnsureHolder(frame, cfg.layer)
    local size = tonumber(cfg.size) or 24
    if size < 1 then size = 1 elseif size > 256 then size = 256 end
    tex:SetSize(size, size)
    local anchor = cfg.anchor or "RIGHT"
    tex:ClearAllPoints()
    tex:SetPoint(anchor, frame, anchor, tonumber(cfg.x) or -7, tonumber(cfg.y) or -4)
    tex:SetAlpha(tonumber(status and status.alpha) or 1)
end

function Happiness.IsEnabled(frame, spec)
    local cfg = Config(frame, spec)
    return frame and frame.MSUFUnitKey == "pet" and cfg and cfg.enabled == true
end

function Happiness.Create(frame, spec)
    local cfg = Config(frame, spec)
    local tex = cfg and EnsureTexture(frame, cfg) or nil
    if tex then
        Layout(frame, tex, cfg, spec and spec.status)
        tex:Hide()
    end
end

function Happiness.Apply(frame, spec)
    local cfg = Config(frame, spec)
    local tex = cfg and EnsureTexture(frame, cfg) or nil
    if not tex then return end
    Layout(frame, tex, cfg, spec and spec.status)
end

function Happiness.GetEvents(frame, spec)
    local status = spec and spec.status
    return status and status.testMode == true and EMPTY_EVENTS or HAPPINESS_EVENTS
end

function Happiness.GetUnitlessEvents(frame, spec)
    local status = spec and spec.status
    return status and status.testMode == true and EMPTY_EVENTS or HAPPINESS_LIFECYCLE_EVENTS
end

function Happiness.Update(frame)
    local tex = frame and frame.petHappinessIndicatorIcon
    local spec = frame and frame.MSUFSpec
    local status = spec and spec.status
    local cfg = status and status.petHappiness
    if not (tex and cfg and cfg.enabled == true and frame.MSUFUnitKey == "pet") then
        if tex then tex:Hide() end
        return
    end

    local happiness
    if status.testMode == true then
        happiness = 3
    elseif type(GetPetHappiness) == "function" then
        if type(HasPetUI) == "function" then
            local _, isHunterPet = HasPetUI()
            if isHunterPet == false then
                tex:Hide()
                return
            end
        end
        local rawHappiness = GetPetHappiness()
        happiness = tonumber(rawHappiness)
    end

    local coords = TEX_COORDS[happiness]
    if not coords then
        tex:Hide()
        return
    end
    tex:SetTexture(TEXTURE)
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    tex:Show()
end

function Happiness.Disable(frame)
    local tex = frame and frame.petHappinessIndicatorIcon
    if tex then tex:Hide() end
end

UF.RegisterElement("PetHappinessIndicator", Happiness, {
    apply = true,
    events = true,
    defaultApply = true,
    forceUpdate = true,
})

_G.MSUF_RequestPetHappinessIndicatorRefresh = function(unit, reason)
    if type(UF.RefreshElements) == "function" then
        return UF.RefreshElements(unit or "pet", { "PetHappinessIndicator" }, reason or "MSUF_PET_HAPPINESS")
    end
    return false
end
