local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Hunter Pet Happiness indicator for the clients that have it.
---
--- Classic Era and TBC expose the global GetPetHappiness. WoW Forever brought
--- happiness back on the Mainline engine as C_PetInfo.GetPetHappiness, and
--- Blizzard's own Forever pet frame shows it. Cataclysm 4.1 removed
--- Happiness/Loyalty, so Mists and Midnight have none: the Mists manifest never
--- lists this file, and on Midnight, which shares the Mainline manifest with
--- Forever, the client gate below returns before anything is registered.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
-- Only an explicit "no" stops the file, so a harness without the client model
-- still gets the element.
if MSUF.Client and MSUF.Client.SupportsPetHappiness == false then return end
local UF = MSUF.UF
if not (UF and type(UF.RegisterElement) == "function") then return end

local CreateFrame = _G.CreateFrame
-- Forever has only the namespaced function, Classic Era and TBC only the global.
local petInfo = _G.C_PetInfo
local GetPetHappiness = type(petInfo) == "table" and petInfo.GetPetHappiness or _G.GetPetHappiness
local IsSecret = _G.issecretvalue
local HasPetUI = _G.HasPetUI
local tonumber = tonumber
local type = type
local floor = math.floor

local EMPTY_EVENTS = {}
-- UNIT_PET carries "player" for the player's pet and can use the UF core's
-- exact dependent-unit route. UNIT_HAPPINESS has no unit payload in Classic
-- (Forever sends one), so it stays on the unitless side, which receives it on
-- every client, just like Blizzard's PetFrame.
local HAPPINESS_EVENTS = { "UNIT_PET" }
local HAPPINESS_LIFECYCLE_EVENTS = { "UNIT_HAPPINESS", "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" }
local TEXTURE = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local TEX_COORDS = {
    [1] = { 0.375, 0.5625, 0, 0.359375 }, -- Unhappy: 75% damage
    [2] = { 0.1875, 0.375, 0, 0.359375 }, -- Content: 100% damage
    [3] = { 0, 0.1875, 0, 0.359375 },     -- Happy: 125% damage
}
-- Each client draws Blizzard's own art. The Classic pet frame uses cells of
-- TEXTURE; the Mainline indicator that reads C_PetInfo (Blizzard_FrameXML/
-- PetHappiness.lua, Forever 1.60.1.70009 and later) uses these atlases. Resolved
-- once: a client without the atlases keeps the texture cells.
local ATLASES = { [1] = "UI-PetMad", [2] = "UI-PetNeutral", [3] = "UI-PetHappiness" }
local textureInfo = _G.C_Texture
local USE_ATLAS = type(petInfo) == "table" and type(petInfo.GetPetHappiness) == "function"
    and type(textureInfo) == "table" and type(textureInfo.GetAtlasInfo) == "function"
    and textureInfo.GetAtlasInfo(ATLASES[3]) ~= nil

local Happiness = { UpdateOnApply = true }

local function Config(frame, spec)
    spec = spec or (frame and frame.MSUFSpec)
    return spec and spec.status and spec.status.petHappiness or nil
end

-- Only this file shows or hides the icon, so its state is cached on the texture
-- and a repeated event writes nothing.
local function HideIcon(tex)
    if tex._msufHappinessShown ~= false then
        tex:Hide()
        tex._msufHappinessShown = false
    end
end

local function ShowIcon(tex, happiness)
    if tex._msufHappiness ~= happiness then
        if USE_ATLAS then
            tex:SetAtlas(ATLASES[happiness])
        else
            local coords = TEX_COORDS[happiness]
            tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
        tex._msufHappiness = happiness
    end
    if tex._msufHappinessShown ~= true then
        tex:Show()
        tex._msufHappinessShown = true
    end
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
        holder = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
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
        tex = PixelLayoutRegion(holder:CreateTexture(nil, "OVERLAY"))
        -- An atlas carries its own file; ShowIcon sets it per state.
        if not USE_ATLAS then tex:SetTexture(TEXTURE) end
        HideIcon(tex)
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
        HideIcon(tex)
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
        if tex then HideIcon(tex) end
        return
    end

    local happiness
    if status.testMode == true then
        happiness = 3
    elseif type(GetPetHappiness) == "function" then
        -- Returns nothing without a hunter pet. A secret value cannot be compared.
        local rawHappiness = GetPetHappiness()
        if IsSecret and IsSecret(rawHappiness) then
            HideIcon(tex)
            return
        end
        happiness = tonumber(rawHappiness)
        -- Only a hunter pet has happiness (Blizzard's pet frame checks the same);
        -- without a value there is nothing to ask.
        if happiness and type(HasPetUI) == "function" then
            local _, isHunterPet = HasPetUI()
            if isHunterPet == false then happiness = nil end
        end
    end

    -- Blizzard knows three states; anything else hides the icon.
    if not TEX_COORDS[happiness] then
        HideIcon(tex)
        return
    end
    ShowIcon(tex, happiness)
end

function Happiness.Disable(frame)
    local tex = frame and frame.petHappinessIndicatorIcon
    if tex then HideIcon(tex) end
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

--- The art of one state (1 unhappy, 2 content, 3 happy; anything else draws
--- happy) in the menu's status icon shape: texture, left, right, top, bottom,
--- atlas. The atlas is set only where this client draws atlases. The unit
--- preview and the Pet page icon strip read it, so they match the live icon.
_G.MSUF_GetPetHappinessIcon = function(happiness)
    if not TEX_COORDS[happiness] then happiness = 3 end
    local coords = TEX_COORDS[happiness]
    return TEXTURE, coords[1], coords[2], coords[3], coords[4], USE_ATLAS and ATLASES[happiness] or nil
end
