--- Pet experience bar for Classic clients with a leveling hunter pet.
--- Blizzard_CharacterFrame/Vanilla and TBC PetPaperDollFrame use the same
--- GetPetExperience and UNIT_PET_EXPERIENCE contract.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local UF = MSUF.UF
local GetPetExperience = _G.GetPetExperience
if not (UF and type(UF.RegisterElement) == "function"
    and type(GetPetExperience) == "function") then return end

local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region) return region end
local CreateFrame = _G.CreateFrame
local HasPetUI = _G.HasPetUI
local IsSecret = _G.issecretvalue
local tonumber = tonumber
local floor = math.floor
local EMPTY = {}
local UNIT_EVENTS = { "UNIT_LEVEL", "UNIT_PET" }
local STATE_EVENTS = { "UNIT_PET_EXPERIENCE", "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local XP = { UpdateOnApply = true }

local function Config(frame, spec)
    spec = spec or (frame and frame.MSUFSpec)
    return spec and spec.status and spec.status.petXP, spec and spec.status
end

local function Clamp(value, fallback, low, high)
    value = floor((tonumber(value) or fallback) + 0.5)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function EnsureBar(frame)
    local holder = frame.petXPBar
    if holder then return holder end
    holder = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    holder:EnableMouse(false)
    holder.back = PixelLayoutRegion(holder:CreateTexture(nil, "BACKGROUND"))
    holder.back:SetAllPoints()
    holder.back:SetColorTexture(0.015, 0.018, 0.035, 0.94)
    holder.fill = PixelLayoutRegion(CreateFrame("StatusBar", nil, holder))
    holder.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    holder.fill:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    holder.fill:SetStatusBarTexture(WHITE)
    holder.fill:SetStatusBarColor(0.68, 0.42, 0.95, 1)
    holder:Hide()
    holder._msufShown = false
    frame.petXPBar = holder
    return holder
end

local function ShowBar(holder)
    if holder._msufShown == true then return end
    holder:Show()
    holder._msufShown = true
end

local function HideBar(holder)
    if holder._msufShown == false then return end
    holder:Hide()
    holder._msufShown = false
end

local function Layout(frame, holder, cfg, status)
    local width = Clamp(cfg.width, 80, 8, 400)
    local height = Clamp(cfg.size, 8, 3, 64)
    if holder._msufWidth ~= width or holder._msufHeight ~= height then
        holder:SetSize(width, height)
        holder._msufWidth, holder._msufHeight = width, height
    end
    local anchor = cfg.anchor or "BOTTOM"
    local x, y = tonumber(cfg.x) or 0, tonumber(cfg.y) or -5
    if holder._msufAnchor ~= anchor or holder._msufX ~= x or holder._msufY ~= y then
        holder:ClearAllPoints()
        holder:SetPoint(anchor, frame, anchor, x, y)
        holder._msufAnchor, holder._msufX, holder._msufY = anchor, x, y
    end
    local layers = UF.Layers
    local base = frame.Health or frame.hpBar or frame
    local level = layers and layers.StatusLevel and layers.StatusLevel(frame, cfg.layer, 7)
        or (((base.GetFrameLevel and base:GetFrameLevel()) or 0) + 10 + Clamp(cfg.layer, 7, 0, 30))
    if holder._msufLevel ~= level then
        holder:SetFrameLevel(level)
        holder._msufLevel = level
    end
    local alpha = tonumber(status and status.alpha) or 1
    if holder._msufAlpha ~= alpha then holder:SetAlpha(alpha); holder._msufAlpha = alpha end
end

function XP.IsEnabled(frame, spec)
    local cfg = Config(frame, spec)
    return frame and frame.MSUFUnitKey == "pet" and cfg and cfg.enabled == true
end

function XP.Create(frame, spec)
    local cfg, status = Config(frame, spec)
    if cfg then Layout(frame, EnsureBar(frame), cfg, status) end
end

function XP.Apply(frame, spec)
    local cfg, status = Config(frame, spec)
    if cfg then Layout(frame, EnsureBar(frame), cfg, status) end
end

function XP.GetEvents(frame, spec)
    local _, status = Config(frame, spec)
    return status and status.testMode == true and EMPTY or UNIT_EVENTS
end

function XP.GetUnitlessEvents(frame, spec)
    local _, status = Config(frame, spec)
    return status and status.testMode == true and EMPTY or STATE_EVENTS
end

function XP.Update(frame)
    local holder = frame and frame.petXPBar
    local cfg, status = Config(frame)
    if not (holder and cfg and cfg.enabled == true and frame.MSUFUnitKey == "pet") then
        if holder then HideBar(holder) end
        return
    end
    local current, maximum
    if status and status.testMode == true then
        current, maximum = 68, 100
    else
        if type(HasPetUI) == "function" then
            local hasUI, isHunter = HasPetUI()
            if hasUI == false or isHunter == false then HideBar(holder); return end
        end
        current, maximum = GetPetExperience()
        if IsSecret and (IsSecret(current) or IsSecret(maximum)) then HideBar(holder); return end
        current, maximum = tonumber(current), tonumber(maximum)
    end
    if not (current and maximum and maximum > 0) then HideBar(holder); return end
    if current < 0 then current = 0 elseif current > maximum then current = maximum end
    if holder._msufMaximum ~= maximum then
        holder.fill:SetMinMaxValues(0, maximum)
        holder._msufMaximum = maximum
    end
    if holder._msufCurrent ~= current then
        holder.fill:SetValue(current)
        holder._msufCurrent = current
    end
    ShowBar(holder)
end

function XP.Disable(frame)
    local holder = frame and frame.petXPBar
    if holder then HideBar(holder) end
end

UF.RegisterElement("PetXPBar", XP, {
    apply = true, events = true, defaultApply = true, forceUpdate = true,
})

_G.MSUF_RequestPetXPBarRefresh = function(unit, reason)
    if type(UF.RefreshElements) == "function" then
        return UF.RefreshElements(unit or "pet", { "PetXPBar" }, reason or "MSUF_PET_XP")
    end
    return false
end
