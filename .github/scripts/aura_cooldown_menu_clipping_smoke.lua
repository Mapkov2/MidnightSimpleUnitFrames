local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local source = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
local sectionHeight = tonumber(source:match(
    'local cooldown = b:CollapsibleSection%(baseId %.%. "_cooldown", "Cooldown Text", (%d+), true%)'
))
local decimalY = tonumber(source:match(
    'BindStyleSlider%(cooldown, "Decimals below sec", 24, (%-%d+),'
))

assert(sectionHeight and decimalY, "unit Aura cooldown menu geometry was not found")
local requiredHeight = math.abs(decimalY) + 24 + 24 + 16
assert(sectionHeight >= requiredHeight,
    ("Aura Cooldown Text clips its final slider: need %d, got %d"):format(requiredHeight, sectionHeight))

print("aura cooldown menu clipping smoke: OK")
