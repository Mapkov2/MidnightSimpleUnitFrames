-- Pins Arena across the interrupt-ready UI/runtime and Assistant action surfaces.
-- Run from the repository root: lua tools/arena_interrupt_ready_smoke.lua

local function Read(path)
    local handle = assert(io.open(path, "rb"), "missing file: " .. path)
    local source = handle:read("*a")
    handle:close()
    return (source:gsub("\r\n", "\n"))
end

local function Contains(source, needle)
    return source:find(needle, 1, true) ~= nil
end

local menu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
assert(Contains(menu, '"Show on Arena castbars"') and Contains(menu, '"kickReadyShowArena"'),
    "Interrupt Ready Menu2 controls omit Arena")
assert(Contains(menu, 'ReadGBool("kickReadyShowArena", false)'),
    "Interrupt Ready Menu2 enablement gate omits Arena")

local bindings = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua")
assert(Contains(bindings, "kickReadyShowBoss kickReadyShowArena"),
    "Castbar reset ownership omits the Arena Interrupt Ready setting")

local registry = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Castbars_Appearance_Interrupts.lua")
assert(Contains(registry, 'RegisterCastbarBoolean("kickReadyShowArena"'),
    "Assistant Registry omits the Arena Interrupt Ready setting")

local inputs = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ActionInputs.lua")
assert(Contains(inputs, '"player", "target", "focus", "boss", "arena"'),
    "Assistant castbar action input rejects Arena")

local actions = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Castbars_Actions.lua")
assert(Contains(actions, "arena = true") and Contains(actions, 'MSUF_SetArenaCastbarTestMode'),
    "Assistant castbar preview/test action omits Arena")

local parser = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Registry.lua")
assert(Contains(parser, 'key = "general.kickReadyShowArena"'),
    "Assistant Interrupt Ready shortcut omits Arena")

_G.MSUF_NS = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
_G.MSUF_DB = {
    general = {
        kickReadyStyle = "fill",
        kickReadyShowArena = true,
    },
}
_G.MSUF_ShouldUseMSUFCastbar = function(unit)
    return unit == "arena"
end

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MSUF", _G.MSUF_NS)
local shouldTint = assert(_G.MSUF_Castbar_ShouldUseInterruptUnavailableColor)
assert(shouldTint({ unit = "arena1" }) == true,
    "Arena castbar did not receive Interrupt Ready fill tint")
_G.MSUF_ShouldUseMSUFCastbar = function() return false end
assert(shouldTint({ unit = "arena1" }) == false,
    "Arena Interrupt Ready fill tint ignored backend ownership")

print("arena_interrupt_ready_smoke: ok")
