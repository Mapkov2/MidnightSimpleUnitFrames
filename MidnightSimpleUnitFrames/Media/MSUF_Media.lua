-- Registers MSUF bundled fonts/textures with LibSharedMedia-3.0 (if available).
-- Drop your actual files in these locations to make them show up in dropdowns.

local LibStub = _G.LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM or not LSM.Register then return end

local base = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"

-- Fonts (keys used by MSUF: FRIZQT/ARIALN/MORPHEUS/SKURRI + these)
LSM:Register("font", "EXPRESSWAY", base .. "Fonts\\Expressway.ttf")
LSM:Register("font", "Expressway (MSUF)", base .. "Fonts\\Expressway.ttf")
LSM:Register("font", "INTER", base .. "Fonts\\Inter.ttf")
LSM:Register("font", "Inter (MSUF)", base .. "Fonts\\Inter.ttf")

-- Statusbar textures
LSM:Register("statusbar", "MSUF Flat",   base .. "Statusbar\\Flat.tga")
LSM:Register("statusbar", "MSUF Smooth", base .. "Statusbar\\Smooth.tga")

