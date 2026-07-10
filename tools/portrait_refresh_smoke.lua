_G = _G or _ENV

local function ResolvePath(primary, fallback)
    local handle = io.open(primary, "r")
    if handle then
        handle:close()
        return primary
    end
    return fallback
end

local commonPath = ResolvePath(
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua",
    "UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua"
)
local portraitPath = ResolvePath(
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua",
    "UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"
)

local function NewRegion(parent)
    local region = { parent = parent, shown = true, frameLevel = 1 }
    function region:GetParent() return self.parent end
    function region:EnableMouse(value) self.mouseEnabled = value end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(value) self.shown = value == true end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function region:SetAllPoints(value) self.allPoints = value or true end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    function region:GetWidth() return self.width or 100 end
    function region:GetHeight() return self.height or 40 end
    function region:SetFrameLevel(level) self.frameLevel = level end
    function region:GetFrameLevel() return self.frameLevel end
    function region:SetTexture(value) self.texture = value; self.atlas = nil end
    function region:SetAtlas(value) self.atlas = value; self.texture = nil end
    function region:SetTexCoord(...) self.texCoord = { ... } end
    function region:SetVertexColor(...) self.vertexColor = { ... } end
    function region:SetAlpha(value) self.alpha = value end
    function region:GetAlpha() return self.alpha or 1 end
    function region:CreateTexture()
        local texture = NewRegion(self)
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function region:HookScript(script, callback)
        self.hooks = self.hooks or {}
        self.hooks[script] = callback
    end
    return region
end

local function CreateFrame(_, _, parent)
    return NewRegion(parent)
end

local registered
local UF = {
    Layers = { PORTRAIT_OFFSET = 6, PORTRAIT_BORDER_OFFSET = 7 },
    Clamp01 = function(value, fallback)
        value = tonumber(value)
        if value == nil then value = fallback or 1 end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end,
    RegisterElement = function(name, element)
        assert(name == "Portrait", "unexpected element registration")
        registered = element
    end,
}

local portraitCalls = 0
local portraitRevision = 1
local now = 1
local guids = { player = "Player-1", target = "Creature-1" }

_G.CreateFrame = CreateFrame
_G.UnitExists = function(unit) return guids[unit] ~= nil end
_G.UnitIsConnected = function() return true end
_G.UnitIsVisible = function() return true end
_G.UnitGUID = function(unit) return guids[unit] end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitReaction = function() return 5 end
_G.UnitThreatSituation = function() return 0 end
_G.UnitGroupRolesAssigned = function() return "NONE" end
_G.InCombatLockdown = function() return false end
_G.GetTime = function() return now end
_G.issecretvalue = function() return false end
_G.SetPortraitTexture = function(texture, unit)
    portraitCalls = portraitCalls + 1
    texture:SetTexture("portrait:" .. tostring(unit) .. ":" .. tostring(portraitRevision))
end
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

local MSUF = { UF = UF, Secrets = { IsNil = function(value) return value == nil end, NotSecret = function() return true end } }
_G.MSUF_NS = MSUF

local commonChunk, commonError = loadfile(commonPath)
assert(commonChunk, commonError)
commonChunk("MidnightSimpleUnitFrames", MSUF)

local sharedEvents = assert(MSUF.UFVisuals and MSUF.UFVisuals.QUEUED_2D_PORTRAIT_EVENTS, "shared portrait event table missing")
assert(sharedEvents.UNIT_ENTERED_VEHICLE == true, "shared enter-vehicle refresh missing")
assert(sharedEvents.UNIT_EXITED_VEHICLE == true, "shared exit-vehicle refresh missing")

local portraitChunk, portraitError = loadfile(portraitPath)
assert(portraitChunk, portraitError)
portraitChunk("MidnightSimpleUnitFrames", MSUF)
local Portrait = assert(registered, "Portrait element was not registered")

local function NewFrame(unit)
    local frame = NewRegion(nil)
    frame.unit = unit
    frame.Health = NewRegion(frame)
    frame.MSUFSpec = {
        height = 40,
        portrait = {
            enabled = true,
            render = "2D",
            shape = "SQUARE",
            side = "LEFT",
            size = 40,
            border = { style = "NONE" },
            bg = { enabled = false },
        },
    }
    return frame
end

local function HasEvent(events, wanted)
    for i = 1, #events do
        if events[i] == wanted then return true end
    end
    return false
end

local player = NewFrame("player")
Portrait.Create(player)
Portrait.Apply(player, player.MSUFSpec)
assert(portraitCalls == 1, "initial portrait apply must call SetPortraitTexture once")
local playerEvents = Portrait.GetEvents(player, player.MSUFSpec)
assert(HasEvent(playerEvents, "UNIT_ENTERED_VEHICLE"), "player enter-vehicle event not registered")
assert(HasEvent(playerEvents, "UNIT_EXITED_VEHICLE"), "player exit-vehicle event not registered")
assert(not HasEvent(playerEvents, "UNIT_HEALTH"), "portrait must not subscribe to health hot events")
assert(not HasEvent(playerEvents, "UNIT_POWER_FREQUENT"), "portrait must not subscribe to power hot events")

for _ = 1, 1000 do
    Portrait.Update(player, "MSUF_UNIT_IDENTITY_VISUAL", "player")
end
assert(portraitCalls == 1, "unchanged identity refreshes must stay on the cached fast path")

portraitRevision = 2
Portrait.Update(player, "UNIT_PORTRAIT_UPDATE", "player")
assert(portraitCalls == 2 and player.portrait.texture == "portrait:player:2", "native portrait event did not force refresh")

portraitRevision = 3
Portrait.Update(player, "UNIT_ENTERED_VEHICLE", "player")
assert(portraitCalls == 3 and player.portrait.texture == "portrait:player:3", "vehicle entry did not bypass the stable GUID cache")

portraitRevision = 4
Portrait.Update(player, "UNIT_EXITED_VEHICLE", "player")
assert(portraitCalls == 4 and player.portrait.texture == "portrait:player:4", "vehicle exit did not bypass the stable GUID cache")

guids.player = "Player-2"
Portrait.Update(player, "MSUF_UNIT_IDENTITY_VISUAL", "player")
assert(portraitCalls == 5 and player.portrait.texture == "portrait:player:4", "GUID change did not refresh portrait")
Portrait.Update(player, "MSUF_UNIT_IDENTITY_VISUAL", "player")
assert(portraitCalls == 5, "stable GUID must not repeat native portrait work")

local target = NewFrame("target")
Portrait.Create(target)
Portrait.Apply(target, target.MSUFSpec)
assert(portraitCalls == 6, "target portrait initial apply missing")
guids.target = "Creature-2"
now = now + 1
Portrait.Update(target, "PLAYER_TARGET_CHANGED", "target")
assert(portraitCalls == 7, "target identity change did not refresh portrait")

print("portrait refresh smoke: ok (cache, native event, vehicle enter/exit, GUID and target changes)")
