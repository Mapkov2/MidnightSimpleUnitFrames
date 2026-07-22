local root = arg and arg[1] or "." -- repository root

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local function Compact(source)
    return (source:gsub("%s+", " "))
end

local function Contains(source, needle, message)
    assert(source:find(needle, 1, true), message)
end

local unitVisuals = Compact(Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua"))
local classPower = Compact(Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"))
Contains(unitVisuals, '"powerSmoothFill", false, "MSUF2_POWER_SMOOTH"',
    "Unit Power Smooth fill still presents an implicit Player-on fallback")
Contains(classPower, '"classPowerSmoothFill", false, ApplyClassPowerSmoothing',
    "Class Resource Smooth fill menu fallback is not opt-in")
Contains(classPower, 'Player, "powerSmoothFill", false, ApplyDetachedPlayerPowerSmoothing',
    "detached Player Power Smooth fill menu fallback is not opt-in")
Contains(classPower, 'Bars, "altManaSmoothFill", false, ApplyClassPowerSmoothing',
    "Alternative Mana Smooth fill menu fallback is not opt-in")

-- Quick Setup is an explicit user action and intentionally remains an opt-in
-- preset for the managed bars.
Contains(classPower, "smoothPowerBar = true, realtimePowerText = true",
    "Class Resources Quick Setup lost its explicit Player Power smoothing choice")
Contains(classPower, "classPowerSmoothFill = true, altManaSmoothFill = true",
    "Class Resources Quick Setup lost its explicit resource smoothing choices")
Contains(classPower, "powerSmoothFill = true,",
    "Class Resources Quick Setup lost its explicit detached-power smoothing choice")

local registryContracts = {
    {
        "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Unitframes_CoreLoop.lua",
        '"Smooth Health Fill", false, MakeAliases',
        "Unit Health Assistant nil fallback is not opt-in",
    },
    {
        "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Unitframes_Power.lua",
        '"Power Bar Smooth Fill", false, MakeAliases',
        "Unit Power Assistant nil fallback is not opt-in",
    },
    {
        "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GroupFramesSettings_Basic.lua",
        '"Smooth Health Fill", false, "visual", aliases',
        "Group Health Assistant nil fallback is not opt-in",
    },
    {
        "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GlobalBarSettings_Base.lua",
        '"Smooth Power Bar", false, {',
        "global Power Assistant nil fallback is not opt-in",
    },
    {
        "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ClassPower_Display.lua",
        '"Class Resource Smooth Fill", false, ClassPowerAliases',
        "Class Resource Assistant nil fallback is not opt-in",
    },
    {
        "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ClassPower_AltMana.lua",
        '"Alternative Mana Smooth Fill", false, {',
        "Alternative Mana Assistant nil fallback is not opt-in",
    },
}
for i = 1, #registryContracts do
    local contract = registryContracts[i]
    Contains(Compact(Read(contract[1])), contract[2], contract[3])
end

local MSUF = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_AutoCoverage_Manifest.lua"))(
    "MidnightSimpleUnitFrames_Assistant", MSUF)
local defaults = assert(MSUF.Assistant and MSUF.Assistant.AutoCoverageManifest
    and MSUF.Assistant.AutoCoverageManifest.defaults, "Assistant AutoCoverage defaults missing")
assert(defaults.bars.smoothPowerBar == false
    and defaults.bars.classPowerSmoothFill == false
    and defaults.bars.altManaSmoothFill == false,
    "Assistant AutoCoverage global/resource smoothing defaults are not opt-in")
for _, scope in ipairs({
    "boss", "focus", "focustarget", "gf_mythicraid", "gf_party", "gf_raid",
    "pet", "player", "target", "targettarget",
}) do
    assert(defaults[scope].smoothFill == false and defaults[scope].powerSmoothFill == false,
        "Assistant AutoCoverage smoothing defaults are not opt-in for " .. scope)
end

print("smoothing opt-in defaults smoke: ok")
