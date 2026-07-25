-- Standalone regression for player opacity ownership in both full and coordinated applies.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local Frame = {}
Frame.__index = Frame

function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:HookScript(name, callback) self.hooks[name] = callback end
function Frame:IsVisible() return true end
function Frame:RegisterEvent(event) self.registered[event] = true end
function Frame:RegisterUnitEvent(event, unit) self.registered[event] = unit end
function Frame:UnregisterEvent(event) self.registered[event] = nil end
function Frame:UnregisterAllEvents()
    for event in pairs(self.registered) do self.registered[event] = nil end
end
function Frame:SetAlpha(alpha)
    self.alpha = alpha
    self.alphaWrites = (self.alphaWrites or 0) + 1
end

local function NewUnitFrame(unit)
    local texture = { alpha = 1, writes = 0 }
    function texture:SetAlpha(alpha)
        self.alpha = alpha
        self.writes = self.writes + 1
    end

    local health = {}
    function health:GetStatusBarTexture() return texture end

    return setmetatable({
        unit = unit,
        unitKey = unit,
        hpBar = health,
        healthTexture = texture,
        alpha = 1,
        scripts = {},
        hooks = {},
        registered = {},
    }, Frame)
end

_G.CreateFrame = function() return NewUnitFrame(nil) end
_G.InCombatLockdown = function() return false end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
_G.issecretvalue = function() return false end

local MSUF = { UF = {} }
_G.MSUF_NS = MSUF

local function Load(relativePath)
    local chunk = assert(loadfile(root .. "/" .. relativePath))
    return chunk("MidnightSimpleUnitFrames", MSUF)
end

Load("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")

MSUF.UFVisuals = {
    UF = MSUF.UF,
    EMPTY_EVENTS = {},
    Clamp01 = function(value, fallback)
        value = tonumber(value)
        if value == nil then value = fallback end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end,
    SetFrameAlpha = function(frame, alpha) frame:SetAlpha(alpha) end,
    SetAlphaCached = function(region, alpha, field, force)
        if not region then return false end
        if force ~= true and region[field] == alpha then return false end
        region[field] = alpha
        region:SetAlpha(alpha)
        return true
    end,
}

Load("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
Load("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua")

local UF = assert(MSUF.UF)
local Metadata = assert(UF.Metadata)
Check(Metadata.defaultApplyMask.Alpha == true,
    "default apply must own Alpha so player opacity is applied at startup/profile refresh")
Check(Metadata.coordinatedApplyMask.Alpha == true,
    "coordinated apply must own Alpha before ApplyService clears its alpha follower")

local function Spec(alpha, unit, rangeActive)
    unit = unit or "player"
    return {
        enabled = true,
        scope = "single",
        key = unit,
        unit = unit,
        alpha = {
            active = alpha < 1,
            hpAlpha = alpha,
            excludeTextPortrait = false,
        },
        range = { active = rangeActive == true, alpha = 0.4, layerMode = "frame" },
    }
end

local player = NewUnitFrame("player")

Check(UF.ApplySpec(player, Spec(0.42)) == true, "default player apply failed")
Check(player.healthTexture.alpha == 0.42,
    "default player apply did not apply configured health opacity")
Check(player._msufAlphaRuntimeCfg and player._msufAlphaRuntimeCfg.hpAlpha == 0.42,
    "default player apply did not compile the Alpha runtime")

Check(UF.ApplySpec(player, Spec(0.67), nil, Metadata.coordinatedApplyMask) == true,
    "coordinated player apply failed")
Check(player.healthTexture.alpha == 0.67,
    "coordinated player apply left the previous opacity active")
Check(player._msufAlphaRuntimeCfg and player._msufAlphaRuntimeCfg.hpAlpha == 0.67,
    "coordinated player apply retained a stale Alpha config")

Check(UF.ApplySpec(player, Spec(1), nil, Metadata.coordinatedApplyMask) == true,
    "coordinated player opacity reset failed")
Check(player.healthTexture.alpha == 1 and player._msufAlphaActive == nil,
    "player opacity transition back to 100% did not reset the Alpha layer")
Check(next(player.registered) == nil and player.scripts.OnUpdate == nil,
    "player Alpha introduced a live event or OnUpdate path")

-- The live range path receives already compiled fixed multipliers. An unchanged
-- value must stop before touching the frame or any child region again.
local target = NewUnitFrame("target")
Check(UF.ApplySpec(target, Spec(0.75, "target", true)) == true,
    "target opacity cold apply failed")
Check(UF.ApplyRangeModifier(target, 0.4, false) == true and target.alpha == 0.4,
    "range fade did not apply its fixed out-of-range multiplier")
local frameWrites = target.alphaWrites
local healthWrites = target.healthTexture.writes
Check(UF.ApplyRangeModifier(target, 0.4, false) == true,
    "cached range multiplier was rejected")
Check(target.alphaWrites == frameWrites and target.healthTexture.writes == healthWrites,
    "unchanged range multiplier repeated alpha region writes")
Check(UF.ApplyRangeModifier(target, 1, false) == true and target.alpha == 1,
    "range fade did not restore its fixed in-range multiplier")
Check(target.alphaWrites == frameWrites + 1 and target.healthTexture.writes == healthWrites,
    "whole-frame range transition touched more regions than required")

io.write("player_alpha_apply_smoke: ok\n")
