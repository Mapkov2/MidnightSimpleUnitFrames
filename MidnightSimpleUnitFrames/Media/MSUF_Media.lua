--- Registers MSUF bundled fonts/textures with LibSharedMedia-3.0 (if available).
--- Keep this file lightweight and load-order safe.

if type(_G.MSUF_RegisterBundledMediaWithLSM) == "function" then
    _G.MSUF_RegisterBundledMediaWithLSM()
    return
end

local LibStub = _G.LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM or type(LSM.Register) ~= "function" then return end

local base = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"

--- Fonts (bundled in Media/Fonts). Keep these paths in sync with the shipped files.
LSM:Register("font", "EXPRESSWAY",                 base .. "Fonts\\Expressway Regular.ttf")
LSM:Register("font", "Expressway Regular (MSUF)",  base .. "Fonts\\Expressway Regular.ttf")
LSM:Register("font", "Expressway (MSUF)",          base .. "Fonts\\Expressway Regular.ttf")
LSM:Register("font", "EXPRESSWAY_BOLD",            base .. "Fonts\\Expressway Bold.ttf")
LSM:Register("font", "Expressway Bold (MSUF)",     base .. "Fonts\\Expressway Bold.ttf")
LSM:Register("font", "EXPRESSWAY_SEMIBOLD",        base .. "Fonts\\Expressway SemiBold.ttf")
LSM:Register("font", "EXPRESSWAY_EXTRABOLD",       base .. "Fonts\\Expressway ExtraBold.ttf")
LSM:Register("font", "EXPRESSWAY_CONDENSED_LIGHT", base .. "Fonts\\Expressway Condensed Light.otf")
LSM:Register("font", "SOUNDSCAPE",                 base .. "Fonts\\Fritz Soundscape.ttf")
LSM:Register("font", "Fritz Soundscape",           base .. "Fonts\\Fritz Soundscape.ttf")

--- Bar / Castbar textures (Media/Bars)
--- IMPORTANT: We intentionally do NOT register the old "MSUF Flat"/"MSUF Smooth" entries anymore,
--- because those pointed at non-existent files (Media/Statusbar/Flat.tga / Smooth.tga) and created
--- invalid dropdown items that cannot be selected.

local baseBars = base .. "Bars\\"

local function Reg(name, file)
    LSM:Register("statusbar", name, baseBars .. file)
end

Reg("MSUF Charcoal",   "Charcoal.tga")
Reg("MSUF Lucent",     "MSUF_Lucent_v2.tga")
Reg("MSUF Minimalist", "Minimalist.tga")
Reg("MSUF Slickrock",  "Slickrock.tga")
Reg("MSUF Smooth",     "MSUF_Smooth.tga")
Reg("MSUF Smooth v2",  "Smoothv2.tga")
Reg("MSUF Smoother",   "smoother.tga")
Reg("MSUF Arcane Pulse",   "MSUF_ArcanePulse.tga")
Reg("MSUF Aurora Silk",    "MSUF_AuroraSilk.tga")
Reg("MSUF Deep Current",   "MSUF_DeepCurrent.tga")
Reg("MSUF Dragon Scale",   "MSUF_DragonScale.tga")
Reg("MSUF Ember Weave",    "MSUF_EmberWeave.tga")
Reg("MSUF Forged Steel",   "MSUF_ForgedSteel.tga")
Reg("MSUF Frosted Quartz", "MSUF_FrostedQuartz.tga")
Reg("MSUF Lunar Mist",     "MSUF_LunarMist.tga")
Reg("MSUF Obsidian Glass", "MSUF_ObsidianGlass.tga")
Reg("MSUF Runic Circuit",  "MSUF_RunicCircuit.tga")
--- Bar art contributed by Aur0r4 (bundled with permission).
Reg("MSUF Dreamy",            "MSUF_Dreamy.tga")
Reg("MSUF Dreamy Soft",       "MSUF_DreamySoft.tga")
Reg("MSUF Dreamy Ultra Soft", "MSUF_DreamyUltraSoft.tga")
Reg("MSUF Foggy",             "MSUF_Foggy.tga")
Reg("MSUF Glass",             "MSUF_Glass.tga")
Reg("MSUF Mirrored Glass",    "MSUF_MirroredGlass.tga")
Reg("Better Blizzard", "BetterBlizzard.blp")

--- DB migration: eliminate broken legacy selections
local function TryMigrate()
    local db = _G.MSUF_DB
    if not db then return false end
    local g = db.general
    if not g then return false end

    local changed = false
    --- Migrate old Midnight texture names to new MSUF names (renaming only)
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
            _G.MSUF_UpdateAllBarTextures()
        end
        if type(_G.MSUF_UpdateCastbarTextures_Immediate) == "function" then
            _G.MSUF_UpdateCastbarTextures_Immediate()
        elseif type(_G.MSUF_UpdateCastbarTextures) == "function" then
            _G.MSUF_UpdateCastbarTextures()
        end
    end
    return changed
end

_G.C_Timer.After(0, function()
    if not TryMigrate() then
        _G.C_Timer.After(2, TryMigrate)
    end
end)
