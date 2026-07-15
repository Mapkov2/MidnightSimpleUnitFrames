_G = _G or _ENV

local eventHandler
local cooldownReads = 0

_G.MSUF_DB = {
    general = {
        kickReadyColor = { ["1"] = 0.1, ["2"] = 0.8, ["3"] = 0.2 },
        kickNotReadyColor = { ["1"] = 0.9, ["2"] = 0.1, ["3"] = 0.2 },
    },
}
_G.MSUF_EnsureDB = function() end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 1337 } }
_G.CreateColor = function(red, green, blue, alpha)
    return { GetRGBA = function() return red, green, blue, alpha end }
end
_G.C_Timer = { NewTimer = function() return { Cancel = function() end } end }
_G.C_Spell = {
    GetSpellCooldownDuration = function()
        cooldownReads = cooldownReads + 1
        return {
            GetRemainingDuration = function() return nil end,
            IsZero = function() return true end,
        }
    end,
}
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, script, callback)
            if script == "OnEvent" then eventHandler = callback end
        end,
    }
end

local scalarCalls = 0
_G.C_CurveUtil = {
    EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
        scalarCalls = scalarCalls + 1
        return value.value and ifTrue or ifFalse
    end,
    EvaluateColorFromBoolean = function()
        error("scalar evaluator should own the Midnight hot path")
    end,
}

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))(
    "MidnightSimpleUnitFrames",
    {}
)

local secretTrue = { secret = true, value = true }
local secretFalse = { secret = true, value = false }
local red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(true, secretTrue)
assert(red == 0.6 and green == 0.6 and blue == 0.6 and alpha == 1)
assert(scalarCalls == 3, "secret RGB must use three scalar evaluations")

red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(true, secretFalse)
assert(red == 0.1 and green == 0.8 and blue == 0.2 and alpha == 1)
assert(scalarCalls == 6)

red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(false, false)
assert(red == 0.9 and green == 0.1 and blue == 0.2 and alpha == 1)
assert(scalarCalls == 6, "plain values must bypass curve evaluation")

red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(true, true)
assert(red == 0.6 and green == 0.6 and blue == 0.6 and alpha == 1)

assert(type(eventHandler) == "function")
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 42, 42, nil, nil)
assert(cooldownReads == 0, "unrelated cooldown events must not read the interrupt Duration")
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 2139, 2139, nil, nil)
assert(cooldownReads == 1, "one cooldown event must reuse one Duration object")

print("interrupt ready perf smoke: ok")
