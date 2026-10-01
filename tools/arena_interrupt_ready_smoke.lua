-- Pins Arena across the interrupt-ready UI and runtime surfaces.
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

local bindings = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings_Reset.lua")
assert(Contains(bindings, "kickReadyShowBoss kickReadyShowArena"),
    "Castbar reset ownership omits the Arena Interrupt Ready setting")

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
-- TBC and Mists publish five arena slots; arena5 shares the arena scope.
assert(shouldTint({ unit = "arena5" }) == true,
    "Arena slot 5 castbar did not receive Interrupt Ready fill tint")
_G.MSUF_ShouldUseMSUFCastbar = function() return false end
assert(shouldTint({ unit = "arena1" }) == false and shouldTint({ unit = "arena5" }) == false,
    "Arena Interrupt Ready fill tint ignored backend ownership")

print("arena_interrupt_ready_smoke: ok")

