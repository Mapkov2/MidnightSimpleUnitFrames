local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local source = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
local shadowControls = assert(source:find(
    'iconStyleGates.shadow[2] = IconStyleAlphaSlider("Shadow Alpha (%)"',
    1,
    true
), "Aura shadow detail controls were not found")
local sharedRefresh = assert(source:find(
    'M.TrackRefresh(ctx, function() iconStyleGates.Apply(true) end)',
    shadowControls,
    true
), "Aura icon-style gates are not registered with the page refresh lifecycle")
local buffOnlySection = assert(source:find(
    'if appearanceGlobalsOnly and previewContainer == "buff" then',
    shadowControls,
    true
), "Buff-only Native Aura Flow section was not found")

assert(sharedRefresh < buffOnlySection,
    "Aura icon-style gate refresh is Buff-only; all Appearance pages must refresh it")

print("aura icon style gate smoke: OK")
