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
local configPath = ResolvePath(
    "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua",
    "UnitFrames/Engine/MSUF_UF_Config.lua"
)
local unitMenuPath = ResolvePath(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"
)
local unitVisualsMenuPath = ResolvePath(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua"
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
    function region:CreateTexture(_, layer, _, sublevel)
        local texture = NewRegion(self)
        texture.layer, texture.sublevel = layer, sublevel
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function region:CreateMaskTexture()
        local mask = NewRegion(self)
        mask.isMask = true
        return mask
    end
    function region:AddMaskTexture(mask)
        self.masks = self.masks or {}
        self.masks[#self.masks + 1] = mask
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
local activeCastIcon, activeChannelIcon
local castInfoReads, channelInfoReads = 0, 0

_G.CreateFrame = CreateFrame
_G.UnitExists = function(unit) return guids[unit] ~= nil end
_G.UnitIsConnected = function() return true end
_G.UnitIsVisible = function() return true end
_G.UnitGUID = function(unit) return guids[unit] end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitCastingInfo = function()
    castInfoReads = castInfoReads + 1
    if activeCastIcon then return "Cast", "Cast", activeCastIcon end
end
_G.UnitChannelInfo = function()
    channelInfoReads = channelInfoReads + 1
    if activeChannelIcon then return "Channel", "Channel", activeChannelIcon end
end
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

local MSUF = {
    UF = UF,
    Secrets = {
        IsNil = function(value) return value == nil end,
        NotSecret = function() return true end,
    },
    PortraitMedia = {
        ResolveClassPortrait = function(class, style)
            if not class then return nil end
            return { texture = "class:" .. tostring(class) .. ":" .. tostring(style) }
        end,
    },
}
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
    frame.MSUFUnitKey = unit
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
assert(player.MSUFPortraitCastIcon == nil, "disabled cast portrait allocated an overlay texture")
local playerEvents = Portrait.GetEvents(player, player.MSUFSpec)
assert(HasEvent(playerEvents, "UNIT_ENTERED_VEHICLE"), "player enter-vehicle event not registered")
assert(HasEvent(playerEvents, "UNIT_EXITED_VEHICLE"), "player exit-vehicle event not registered")
assert(not HasEvent(playerEvents, "UNIT_HEALTH"), "portrait must not subscribe to health hot events")
assert(not HasEvent(playerEvents, "UNIT_POWER_FREQUENT"), "portrait must not subscribe to power hot events")
assert(not HasEvent(playerEvents, "UNIT_SPELLCAST_START"), "disabled cast portrait registered spellcast events")
assert(castInfoReads == 0 and channelInfoReads == 0, "disabled cast portrait queried cast APIs")

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

player.MSUFSpec.portrait.castSpellIcon = true
Portrait.Apply(player, player.MSUFSpec)
local castEvents = Portrait.GetEvents(player, player.MSUFSpec)
local castOverlay = assert(player.MSUFPortraitCastIcon, "enabled cast portrait did not create its lazy overlay")
assert(castOverlay ~= player.portrait, "cast overlay reused the expensive base portrait texture")
assert(castOverlay.sublevel == 1, "cast overlay is not layered above the base portrait")
assert(castOverlay.masks and castOverlay.masks[1] == player.MSUFPortraitHolder.mask,
    "cast overlay does not share the configured portrait mask")
assert(HasEvent(castEvents, "UNIT_SPELLCAST_START"), "enabled cast portrait did not register cast start")
assert(HasEvent(castEvents, "UNIT_SPELLCAST_CHANNEL_STOP"), "enabled cast portrait did not register channel stop")
assert(HasEvent(castEvents, "UNIT_SPELLCAST_EMPOWER_START"), "enabled cast portrait did not register empower start")
assert(not HasEvent(castEvents, "UNIT_SPELLCAST_DELAYED"), "cast portrait registered a timing-only event")

activeCastIcon = 136243
local channelReadsBeforeCastStart = channelInfoReads
local portraitBeforeCast = player.portrait.texture
local portraitCallsBeforeCast = portraitCalls
Portrait.Update(player, "UNIT_SPELLCAST_START", "player")
assert(player.portrait.texture == portraitBeforeCast, "cast start overwrote the cached unit portrait")
assert(castOverlay.texture == activeCastIcon, "cast start did not paint the overlay with the spell icon")
assert(player.portrait.shown == false and castOverlay.shown == true,
    "cast start did not switch from the base portrait to its overlay")
assert(player._msufPortraitCastIconActive == true, "cast portrait active state missing")
assert(channelInfoReads == channelReadsBeforeCastStart, "cast start queried the channel API")

activeCastIcon = nil
Portrait.Update(player, "UNIT_SPELLCAST_STOP", "player")
assert(portraitCalls == portraitCallsBeforeCast, "unchanged cast stop rebuilt the native unit portrait")
assert(player.portrait.texture == portraitBeforeCast, "cast stop changed the cached unit portrait")
assert(player.portrait.shown == true and castOverlay.shown == false,
    "cast stop did not restore base/overlay visibility")
assert(player._msufPortraitCastIconActive == nil, "cast portrait active state survived cast stop")

activeChannelIcon = 136235
local castReadsBeforeChannelStart = castInfoReads
Portrait.Update(player, "UNIT_SPELLCAST_CHANNEL_START", "player")
assert(castOverlay.texture == activeChannelIcon and castOverlay.shown == true,
    "channel start did not show its spell icon overlay")
assert(castInfoReads == castReadsBeforeChannelStart, "channel start queried the casting API")
activeChannelIcon = nil
Portrait.Update(player, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
assert(portraitCalls == portraitCallsBeforeCast, "unchanged channel stop rebuilt the native unit portrait")
assert(player.portrait.texture == portraitBeforeCast and castOverlay.shown == false,
    "channel stop did not reveal the unchanged unit portrait")

-- A genuine portrait bust received while the spell icon is visible must stay
-- pending and refresh the hidden base once when the cast ends.
activeCastIcon = 136243
Portrait.Update(player, "UNIT_SPELLCAST_START", "player")
portraitRevision = 5
Portrait.Update(player, "UNIT_PORTRAIT_UPDATE", "player")
assert(portraitCalls == portraitCallsBeforeCast, "visible cast icon eagerly refreshed its hidden base portrait")
activeCastIcon = nil
Portrait.Update(player, "UNIT_SPELLCAST_INTERRUPTED", "player")
assert(portraitCalls == portraitCallsBeforeCast + 1, "deferred portrait bust was lost at cast end")
assert(player.portrait.texture == "portrait:player:5", "deferred portrait bust restored stale unit art")

activeChannelIcon = 136235
local callsBeforeEmpower = portraitCalls
Portrait.Update(player, "UNIT_SPELLCAST_EMPOWER_START", "player")
assert(castOverlay.texture == activeChannelIcon and castOverlay.shown == true,
    "empower start did not use the channel icon overlay")
activeChannelIcon = nil
Portrait.Update(player, "UNIT_SPELLCAST_EMPOWER_STOP", "player")
assert(portraitCalls == callsBeforeEmpower, "unchanged empower stop rebuilt the native unit portrait")

local classFrame = NewFrame("player")
classFrame.MSUFSpec.portrait.render = "CLASS"
classFrame.MSUFSpec.portrait.classStyle = "BLIZZARD"
classFrame.MSUFSpec.portrait.castSpellIcon = true
Portrait.Create(classFrame)
Portrait.Apply(classFrame, classFrame.MSUFSpec)
local classBase = classFrame.portrait.texture
local classOverlay = assert(classFrame.MSUFPortraitCastIcon, "CLASS portrait did not create its cast overlay")
local callsBeforeClassCast = portraitCalls
activeCastIcon = 136243
Portrait.Update(classFrame, "UNIT_SPELLCAST_START", "player")
assert(classFrame.portrait.texture == classBase and classOverlay.texture == activeCastIcon,
    "CLASS cast start overwrote the cached class portrait")
activeCastIcon = nil
Portrait.Update(classFrame, "UNIT_SPELLCAST_FAILED", "player")
assert(portraitCalls == callsBeforeClassCast and classFrame.portrait.texture == classBase,
    "CLASS cast failure rebuilt or changed the cached class portrait")
assert(classFrame.portrait.shown == true and classOverlay.shown == false,
    "CLASS cast failure did not reveal the cached class portrait")

player.MSUFSpec.portrait.castSpellIcon = false
Portrait.Apply(player, player.MSUFSpec)
assert(castOverlay.shown == false and player.portrait.shown == true,
    "disabling the cast icon option left the overlay visible")
local readsBeforeDisabledUpdate = castInfoReads + channelInfoReads
Portrait.Update(player, "UNIT_PORTRAIT_UPDATE", "player")
assert(castInfoReads + channelInfoReads == readsBeforeDisabledUpdate, "disabled cast portrait retained API overhead")
assert(not HasEvent(Portrait.GetEvents(player, player.MSUFSpec), "UNIT_SPELLCAST_START"), "disabled cast portrait retained spellcast events")

local function ReadFile(path)
    local handle = assert(io.open(path, "r"))
    local text = handle:read("*a")
    handle:close()
    return text
end
local configSource = ReadFile(configPath)
local unitMenuSource = ReadFile(unitMenuPath)
local unitVisualsMenuSource = ReadFile(unitVisualsMenuPath)
assert(configSource:find("out.portrait.castSpellIcon = conf.portraitCastSpellIcon == true", 1, true), "portrait cast option is not compiled")
assert(unitMenuSource:find("portraitCastSpellIcon", 1, true), "portrait copy scope lost the cast icon option")
assert(unitVisualsMenuSource:find("Show cast spell icon in portrait", 1, true), "portrait menu toggle missing")

print("portrait refresh smoke: ok (cache, lifecycle, optional event routing, cast/channel icon swap, zero disabled API reads)")
