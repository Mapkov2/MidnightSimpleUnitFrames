-- Registers MSUF bundled fonts/textures with LibSharedMedia-3.0 (if available).
-- Drop your actual files in these locations to make them show up in dropdowns.

local LibStub = _G.LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM or not LSM.Register then return end

local base = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"

-- Fonts (keys used by MSUF: FRIZQT/ARIALN/MORPHEUS/SKURRI + these)
pcall(LSM.Register, LSM, "font", "EXPRESSWAY",                 base .. "Fonts\\Expressway Regular.ttf")
pcall(LSM.Register, LSM, "font", "Expressway (MSUF)",          base .. "Fonts\\Expressway Regular.ttf")
pcall(LSM.Register, LSM, "font", "EXPRESSWAY_BOLD",            base .. "Fonts\\Expressway Bold.ttf")
pcall(LSM.Register, LSM, "font", "Expressway Bold (MSUF)",     base .. "Fonts\\Expressway Bold.ttf")
pcall(LSM.Register, LSM, "font", "EXPRESSWAY_SEMIBOLD",        base .. "Fonts\\Expressway SemiBold.ttf")
pcall(LSM.Register, LSM, "font", "EXPRESSWAY_EXTRABOLD",       base .. "Fonts\\Expressway ExtraBold.ttf")
pcall(LSM.Register, LSM, "font", "EXPRESSWAY_CONDENSED_LIGHT", base .. "Fonts\\Expressway Condensed Light.otf")

-- Statusbar textures
local baseBars = base .. "Bars\\"
local function RegStatusbar(name, file)
    pcall(LSM.Register, LSM, "statusbar", name, baseBars .. file)
end

RegStatusbar("MSUF Charcoal",   "Charcoal.tga")
RegStatusbar("MSUF Minimalist", "Minimalist.tga")
RegStatusbar("MSUF Slickrock",  "Slickrock.tga")
RegStatusbar("MSUF Smooth",     "MSUF_Smooth.tga")
RegStatusbar("MSUF Smooth v2",  "Smoothv2.tga")
RegStatusbar("MSUF Smoother",   "smoother.tga")
