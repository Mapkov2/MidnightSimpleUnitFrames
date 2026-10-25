-- Independent UF element for the optional Class Resources Player health bar.
local _, MSUF = ...
local FILE = "UnitFrames/Engine/Elements/MSUF_UF_PlayerHP.lua"
local UF = MSUF.UF
local function RequireMethod(provider, name, method)
    if type(provider) ~= "table" or type(provider[method]) ~= "function" then
        error("MSUF: missing required dependency '" .. name .. "." .. method .. "' required by " .. FILE, 2)
    end
    return provider[method]
end
local RegisterElement = RequireMethod(UF, "UF", "RegisterElement")
local AttachFrame = RequireMethod(UF, "UF", "AttachFrame")
local ApplyElement = RequireMethod(UF, "UF", "ApplyElementToFrame")
local SetFrameSpec = RequireMethod(UF, "UF", "SetFrameSpec")
if type(UF.attachedFrames) ~= "table" then
    error("MSUF: missing required dependency 'UF.attachedFrames' required by " .. FILE, 2)
end
local function RequireFunction(name)
    local value = MSUF.Require(name, FILE)
    if type(value) ~= "function" then
        error("MSUF: missing required dependency '" .. name .. "' required by " .. FILE, 2)
    end
    return value
end
local InCombat = RequireFunction("MSUF_IsPlayerInCombat")
local UnitAffectingCombat = RequireFunction("UnitAffectingCombat")
local PixelLayoutRegion = RequireFunction("MSUF_PixelLayoutRegion")
-- These providers precede the visual/element XML on every client. Validate
-- their callable shape before the controller binds any injected painter APIs.
for _, name in ipairs({ "MSUF_GetFontPath", "MSUF_GetFontFlags", "MSUF_FontPathEquals",
    "MSUF_MarkFontApplyFailed", "MSUF_UF_NormalizeClassPowerShape", "MSUF_UF_NormalizePlayerHPShape", "MSUF_UF_ShapeOutlineAlpha" }) do
    RequireFunction(name)
end
local function Combat(event)
    return InCombat(event) or UnitAffectingCombat("player") == true
end
local CPConst = MSUF.Require("MSUF_CP_CONST", FILE)
local BuilderRegistry = RequireMethod(CPConst, "MSUF_CP_CONST", "BuilderRegistry")
local builders = BuilderRegistry("MSUF_CP_CORE_BUILDERS")
local BuildVisual = RequireMethod(builders, "ClassPower builders", "PLAYER_HP_VISUAL")
local InjectedAPI = RequireMethod(builders, "ClassPower builders", "PLAYER_HP_API")
local PHP = { visible = false }
local PlayerHP = { State = PHP }
UF.PlayerHP = PlayerHP
local visual, _cpDB, GetPlayerFrame, CreateFrame, pendingDriver

-- Each resource has its own UF host. Applying a player spec to the secure
-- unit button must never enable, disable or detach this independent element.
PlayerHP.Routes = { events = true, reshow = true, forceUpdate = true }
PlayerHP.events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }
PlayerHP.unitlessEvents = { "PLAYER_DEAD", "PLAYER_ALIVE" }
local function ElementUpdate(_, event)
    if event == "MSUF_UF_ONSHOW" and PHP.applying then return end
    return visual.Update(event)
end
PlayerHP.Update = ElementUpdate
PlayerHP.NoDispatchUpdates = { [ElementUpdate] = true }

function PlayerHP.IsEnabled(frame)
    return frame == PHP.frame and _cpDB.bars.playerHPBarEnabled == true
end

function PlayerHP.Apply(frame)
    PHP.applying = true
    visual.Apply(PHP.owner or GetPlayerFrame())
    PHP.applying = nil
end

function PlayerHP.Enable(frame)
    if not PlayerHP.IsEnabled(frame) then return false end
    if not PHP.visible then PlayerHP.Apply(frame) end
end

function PlayerHP.Disable()
    visual.Hide()
end

local function FlushPending(_, event)
    if Combat(event) then return end
    if PHP.pendingDisable then return PlayerHP.Hide() end
    return PlayerHP.Refresh(PHP.owner)
end

local function Defer(disable)
    PHP.pending, PHP.pendingDisable = true, disable
    if not pendingDriver then
        pendingDriver = PixelLayoutRegion(CreateFrame("Frame"))
        pendingDriver:SetScript("OnEvent", FlushPending)
    end
    pendingDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
end

function PlayerHP.Refresh(playerFrame)
    PHP.owner = playerFrame or GetPlayerFrame()
    if Combat() then return Defer(false) end
    if not (_cpDB.bars and _cpDB.bars.playerHPBarEnabled == true) then return PlayerHP.Hide() end
    if not visual.Create(PHP.owner) then return false end
    local frame = PHP.frame
    if not UF.attachedFrames[frame] then
        AttachFrame(frame, { scope = "resource" })
        SetFrameSpec(frame, { unit = "player", key = "playerHP", enabled = true, scope = "resource" })
    end
    -- The resource option is the only enablement predicate. ApplyResource
    -- retains the native sinks, layout stamps and ResourceVisibility ownership.
    local applied = ApplyElement(frame, "PlayerHP")
    if applied ~= false then
        PHP.pending, PHP.pendingDisable = nil, nil
        if pendingDriver then pendingDriver:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end
    return applied
end

function PlayerHP.Hide()
    if Combat() then return Defer(true) end
    if PHP.frame and UF.attachedFrames[PHP.frame] then
        PHP.frame:DisableElement("PlayerHP")
    else
        visual.Hide()
    end
    PHP.pending, PHP.pendingDisable = nil, nil
    if pendingDriver then pendingDriver:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end

local function Refresh(playerFrame) return PlayerHP.Refresh(playerFrame) end
local function ApplyFontPublic()
    PHP._fontStamp = nil
    if Combat() then return Defer(false) end
    visual.ApplyFont()
end

local function RefreshTextures(playerFrame, fonts)
    PHP._textureStamp = nil
    if fonts then PHP._fontStamp = nil end
    return PlayerHP.Refresh(playerFrame)
end

RegisterElement("PlayerHP", PlayerHP, { apply = true, scope = "resource" })

function PlayerHP.Bind(E)
    GetPlayerFrame = RequireMethod(E, "PlayerHP injected APIs", "GetPlayerFrame")
    CreateFrame = InjectedAPI(E.CreateFrame, "PlayerHP injected APIs.CreateFrame")
    RequireMethod(E, "PlayerHP injected APIs", "ResolveTexture")
    RequireMethod(E, "PlayerHP injected APIs", "UnitClass")
    _cpDB = E._cpDB
    if type(_cpDB) ~= "table" then
        error("MSUF: missing required dependency 'PlayerHP injected _cpDB' required by " .. FILE, 2)
    end
    -- Preserve the cold injected-state boundary while the engine retains one
    -- authoritative state and its existing host on every later refresh.
    if PHP.frame == nil and E.PHP ~= nil then
        if type(E.PHP) ~= "table" then
            error("MSUF: invalid PlayerHP injected state required by " .. FILE, 2)
        end
        PHP, PlayerHP.State = E.PHP, E.PHP
    end
    E.PHP = PHP
    visual = BuildVisual(E)
    RequireMethod(visual, "PlayerHP visual", "Apply")
    RequireMethod(visual, "PlayerHP visual", "Create")
    RequireMethod(visual, "PlayerHP visual", "Update")
    RequireMethod(visual, "PlayerHP visual", "ApplyFont")
    RequireMethod(visual, "PlayerHP visual", "Hide")
    return {
        PHP = PHP, Refresh = Refresh, Update = visual.Update,
        ApplyFont = ApplyFontPublic, RefreshTextures = RefreshTextures, Hide = PlayerHP.Hide,
    }
end

function PlayerHP.ValidateBinding(binding)
    RequireMethod(binding, "UF.PlayerHP binding", "Refresh")
    RequireMethod(binding, "UF.PlayerHP binding", "Hide")
    RequireMethod(binding, "UF.PlayerHP binding", "ApplyFont")
    RequireMethod(binding, "UF.PlayerHP binding", "RefreshTextures")
    if type(binding.PHP) ~= "table" then
        error("MSUF: missing required dependency 'UF.PlayerHP binding.PHP' required by " .. FILE, 2)
    end
end

-- Compatibility only: the controller binds providers and forwards cold calls.
builders.PLAYER_HP = PlayerHP.Bind
builders.PLAYER_HP_REQUIRE = function(owner)
    return RequireMethod(owner, "UF.PlayerHP", "ValidateBinding")
end
