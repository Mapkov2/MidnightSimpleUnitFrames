-- Registers MSUF bundled fonts/textures with LibSharedMedia-3.0 (if available).
-- Keep this file lightweight and load-order safe.

local LibStub = _G.LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM or type(LSM.Register) ~= "function" then return end

local base = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"

-- -----------------------------------------------------------------------------
-- Fonts (if present)
-- -----------------------------------------------------------------------------
-- These are safe no-ops if the files are missing (LSM will still register, but user won't pick them).
-- Font registration is also done in MSUF_Libs.lua in a load-order-safe way; keeping this here is harmless.

pcall(LSM.Register, LSM, "font", "EXPRESSWAY",        base .. "Fonts\\Expressway.ttf")
pcall(LSM.Register, LSM, "font", "Expressway (MSUF)", base .. "Fonts\\Expressway.ttf")
pcall(LSM.Register, LSM, "font", "INTER",             base .. "Fonts\\Inter.ttf")
pcall(LSM.Register, LSM, "font", "Inter (MSUF)",      base .. "Fonts\\Inter.ttf")

-- -----------------------------------------------------------------------------
-- Bar / Castbar textures (Media/Bars)
-- -----------------------------------------------------------------------------
-- IMPORTANT: We intentionally do NOT register the old "MSUF Flat"/"MSUF Smooth" entries anymore,
-- because those pointed at non-existent files (Media/Statusbar/Flat.tga / Smooth.tga) and created
-- invalid dropdown items that cannot be selected.

local baseBars = base .. "Bars\\"

local function Reg(name, file)
    pcall(LSM.Register, LSM, "statusbar", name, baseBars .. file)
end

Reg("MSUF Charcoal",   "Charcoal.tga")
Reg("MSUF Minimalist", "Minimalist.tga")
Reg("MSUF Slickrock",  "Slickrock.tga")
Reg("MSUF Smooth",     "MSUF_Smooth.tga")
Reg("MSUF Smooth v2",  "Smoothv2.tga")
Reg("MSUF Smoother",   "smoother.tga")

-- -----------------------------------------------------------------------------
-- DB migration: eliminate broken legacy selections
-- -----------------------------------------------------------------------------
local function TryMigrate()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end
    local g = db.general
    if type(g) ~= "table" then return false end

    local changed = false
    -- Migrate old Midnight texture names to new MSUF names (renaming only)
    local map = {
        ["Midnight Charcoal"] = "MSUF Charcoal",
        ["Midnight Minimalist"] = "MSUF Minimalist",
        ["Midnight Slickrock"] = "MSUF Slickrock",
        ["Midnight Smooth"] = "MSUF Smooth",
        ["Midnight Smooth v2"] = "MSUF Smooth v2",
        ["Midnight Smoother"] = "MSUF Smoother",
    }
    if type(g.barTexture) == "string" and map[g.barTexture] then
        g.barTexture = map[g.barTexture]
        changed = true
    end
    if type(g.castbarTexture) == "string" and map[g.castbarTexture] then
        g.castbarTexture = map[g.castbarTexture]
        changed = true
    end
    if g.barTexture == "MSUF Flat" then
        g.barTexture = "Solid"
        changed = true
    elseif g.barTexture == "MSUF Smooth" then
        g.barTexture = "MSUF Smooth"
        changed = true
    end

    if g.castbarTexture == "MSUF Flat" then
        g.castbarTexture = "Solid"
        changed = true
    elseif g.castbarTexture == "MSUF Smooth" then
        g.castbarTexture = "MSUF Smooth"
        changed = true
    end

    if changed then
        if type(_G.MSUF_UpdateAllBarTextures) == "function" then
            pcall(_G.MSUF_UpdateAllBarTextures)
        end
        if type(_G.MSUF_UpdateCastbarTextures_Immediate) == "function" then
            pcall(_G.MSUF_UpdateCastbarTextures_Immediate)
        elseif type(_G.MSUF_UpdateCastbarTextures) == "function" then
            pcall(_G.MSUF_UpdateCastbarTextures)
        end
    end
    return changed
end

if _G.C_Timer and type(_G.C_Timer.After) == "function" then
    _G.C_Timer.After(0, function()
        if not TryMigrate() then
            _G.C_Timer.After(2, TryMigrate)
        end
    end)
end
