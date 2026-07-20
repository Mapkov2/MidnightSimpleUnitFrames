-- Focused asset and registration regression for the 5.74 texture backport.
local textures = {
    { "MSUF Lucent", "MSUF_Lucent_v2.tga" },
    { "MSUF Arcane Pulse", "MSUF_ArcanePulse.tga" },
    { "MSUF Aurora Silk", "MSUF_AuroraSilk.tga" },
    { "MSUF Deep Current", "MSUF_DeepCurrent.tga" },
    { "MSUF Dragon Scale", "MSUF_DragonScale.tga" },
    { "MSUF Ember Weave", "MSUF_EmberWeave.tga" },
    { "MSUF Forged Steel", "MSUF_ForgedSteel.tga" },
    { "MSUF Frosted Quartz", "MSUF_FrostedQuartz.tga" },
    { "MSUF Lunar Mist", "MSUF_LunarMist.tga" },
    { "MSUF Obsidian Glass", "MSUF_ObsidianGlass.tga" },
    { "MSUF Runic Circuit", "MSUF_RunicCircuit.tga" },
}

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local libs = Read("MidnightSimpleUnitFrames/Foundation/MSUF_Libs.lua")
local media = Read("MidnightSimpleUnitFrames/Media/MSUF_Media.lua")
for _, spec in ipairs(textures) do
    local name, fileName = spec[1], spec[2]
    local path = "MidnightSimpleUnitFrames/Media/Bars/" .. fileName
    local file = assert(io.open(path, "rb"), "missing texture: " .. path)
    local size = assert(file:seek("end"))
    file:close()
    assert(size == 32812, "unexpected texture size for " .. fileName)
    local registration = string.format('Reg("%s"', name)
    assert(libs:find(registration, 1, true), "Foundation registration missing for " .. name)
    assert(media:find(registration, 1, true), "Media registration missing for " .. name)
end

print("bar_textures_backport_smoke: ok")
