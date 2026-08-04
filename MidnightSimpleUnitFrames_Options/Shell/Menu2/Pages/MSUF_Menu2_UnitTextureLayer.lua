local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local T = M.Theme or {}
local UP = M.UnitPage or {}
local VTP = M.ValueTextPairs
local abs = math.abs
local floor = math.floor
local max = math.max
local min = math.min

-- Decorative texture layer section (bottom of every unit page).
-- Three independent layer slots per frame, edited through one shared control
-- set: the slot bar picks the layer, the category bar picks the sub-page
-- (General / Placement / Style / Visibility), and every binding resolves its
-- DB key against the selected slot at read/write time. The runtime lives in
-- UnitFrames/Effects/MSUF_UF_TextureLayer.lua and re-stamps cold path only.
local SLOT_PREFIXES = { "texLayer", "texLayer2", "texLayer3" }
local TEXLAYER_ANCHORS = VTP "TOPLEFT=Top Left|TOP=Top|TOPRIGHT=Top Right|LEFT=Left|CENTER=Center|RIGHT=Right|BOTTOMLEFT=Bottom Left|BOTTOM=Bottom|BOTTOMRIGHT=Bottom Right"
local TEXLAYER_STRATA = VTP "AUTO=Frame default|BACKGROUND=Background|LOW=Low|MEDIUM=Medium|HIGH=High|DIALOG=Dialog|TOOLTIP=Tooltip"
local TEXLAYER_ANCHOR_TARGETS = VTP "FRAME=Whole frame|HEALTH=Health bar|POWER=Power bar|PORTRAIT=Portrait"
local TEXLAYER_VISIBILITY = VTP "ALWAYS=Always|COMBAT=In combat only|OOC=Out of combat only"
local TEXLAYER_COLOR_MODES = VTP "CUSTOM=Custom color|CLASS=Class color"
local TEXLAYER_SOURCE_MODES = VTP "PACK=MSUF asset|SHAREDMEDIA=SharedMedia|CUSTOM=Custom file path"
local TEXLAYER_SIZE_MODES = VTP "FRAME=Fit frame width + height|HEIGHT=Square ornament from frame height|MANUAL=Manual width + height"
local TEXLAYER_EDGE_ATTACH = VTP "FREE=Free position|LEFT=Follow left frame edge|RIGHT=Follow right frame edge"
local PAD_DIRECTION_SUFFIXES = { UP = "GradientDirUp", LEFT = "GradientDirLeft", RIGHT = "GradientDirRight", DOWN = "GradientDirDown" }
local TEXLAYER_TABS = M.WordList "general placement style visibility"
local TEXLAYER_TAB_TEXTS = { general = "General", placement = "Placement", style = "Style", visibility = "Visibility" }
local TEXLAYER_SECTION_H = 572
local TEXLAYER_CARD_Y = -108
local TEXLAYER_CARD_H = 430

-- The design catalog intentionally lives in the load-on-demand Options addon.
-- Runtime only sees the selected texture path and therefore pays no catalog,
-- lookup, preview or preset cost while the options are closed.
local TEXLAYER_PACK_ROOT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\TextureLayers\\"
local TEXLAYER_PACK_PRESETS = {
    { value = "MIDNIGHT_RAIL",       text = "No Portrait | Midnight Rail",       file = "msuf_texlayer_midnight_rail.png" },
    { value = "MIDNIGHT_VECTOR",     text = "No Portrait | Midnight Vector",     file = "msuf_texlayer_midnight_vector.png" },
    { value = "VOIDGLASS_HORIZON",   text = "No Portrait | Voidglass Horizon",   file = "msuf_texlayer_voidglass_horizon.png" },
    { value = "TITANWEAVE",          text = "No Portrait | Titanweave",          file = "msuf_texlayer_titanweave.png" },
    { value = "RUNEBLADE",           text = "No Portrait | Runeblade",           file = "msuf_texlayer_runeblade.png" },
    { value = "EMBERFORGE",          text = "No Portrait | Emberforge",          file = "msuf_texlayer_emberforge.png" },
    { value = "FROSTWARD",           text = "No Portrait | Frostward",           file = "msuf_texlayer_frostward.png" },
    { value = "WILDWOOD_NIGHT",      text = "No Portrait | Wildwood Night",      file = "msuf_texlayer_wildwood_night.png" },
    { value = "DAWNSTEEL",           text = "No Portrait | Dawnsteel",           file = "msuf_texlayer_dawnsteel.png" },
    { value = "BLOODSTONE_EDGE",     text = "No Portrait | Bloodstone Edge",     file = "msuf_texlayer_bloodstone_edge.png" },
    { value = "ASTRAL_CIRCUIT",      text = "No Portrait | Astral Circuit",      file = "msuf_texlayer_astral_circuit.png" },
    { value = "GRIMTHORN",           text = "No Portrait | Grimthorn",           file = "msuf_texlayer_grimthorn.png" },
    { value = "MIN_BASE_HAIRLINE",       text = "Minimal Base | Hairline",       file = "msuf_texlayer_min_base_hairline.png", minimal = true },
    { value = "MIN_BASE_DOUBLE_RAIL",    text = "Minimal Base | Double Rail",    file = "msuf_texlayer_min_base_double_rail.png", minimal = true },
    { value = "MIN_BASE_OPEN_BRACKET",   text = "Minimal Base | Open Bracket",   file = "msuf_texlayer_min_base_open_bracket.png", minimal = true },
    { value = "MIN_BASE_CENTER_NOTCH",   text = "Minimal Base | Center Notch",   file = "msuf_texlayer_min_base_center_notch.png", minimal = true },
    { value = "MIN_BASE_STEPPED_TECH",   text = "Minimal Base | Stepped Tech",   file = "msuf_texlayer_min_base_stepped_tech.png", minimal = true },
    { value = "MIN_BASE_ARCANE_CAPSULE", text = "Minimal Base | Arcane Capsule", file = "msuf_texlayer_min_base_arcane_capsule.png", minimal = true },
    { value = "MIN_BASE_SPLIT_HORIZON",  text = "Minimal Base | Split Horizon",  file = "msuf_texlayer_min_base_split_horizon.png", minimal = true },
    { value = "MIN_BASE_ASYM_VECTOR",    text = "Minimal Base | Asym Vector",    file = "msuf_texlayer_min_base_asym_vector.png", minimal = true },
    { value = "MIN_BASE_SHARD_CORNERS",  text = "Minimal Base | Shard Corners",  file = "msuf_texlayer_min_base_shard_corners.png", minimal = true },
    { value = "MIN_BASE_ECLIPSE_ARC",    text = "Minimal Base | Eclipse Arc",    file = "msuf_texlayer_min_base_eclipse_arc.png", minimal = true },
    { value = "MIN_OVERLAY_MICRO_DOTS",    text = "Minimal Accent | Micro Dots",    file = "msuf_texlayer_min_overlay_micro_dots.png", minimal = true },
    { value = "MIN_OVERLAY_RUNE_TICKS",    text = "Minimal Accent | Rune Ticks",    file = "msuf_texlayer_min_overlay_rune_ticks.png", minimal = true },
    { value = "MIN_OVERLAY_CORNER_GLINT",  text = "Minimal Accent | Corner Glint",  file = "msuf_texlayer_min_overlay_corner_glint.png", minimal = true },
    { value = "MIN_OVERLAY_CENTER_SIGIL",  text = "Minimal Accent | Center Sigil",  file = "msuf_texlayer_min_overlay_center_sigil.png", minimal = true },
    { value = "MIN_OVERLAY_ENERGY_SWEEP",  text = "Minimal Accent | Energy Sweep",  file = "msuf_texlayer_min_overlay_energy_sweep.png", minimal = true },
    { value = "CLASS_WARRIOR",     text = "Class Fantasy | Warrior",      file = "msuf_texlayer_class_warrior.png", minimal = true },
    { value = "CLASS_PALADIN",     text = "Class Fantasy | Paladin",      file = "msuf_texlayer_class_paladin.png", minimal = true },
    { value = "CLASS_HUNTER",      text = "Class Fantasy | Hunter",       file = "msuf_texlayer_class_hunter.png", minimal = true },
    { value = "CLASS_ROGUE",       text = "Class Fantasy | Rogue",        file = "msuf_texlayer_class_rogue.png", minimal = true },
    { value = "CLASS_PRIEST",      text = "Class Fantasy | Priest",       file = "msuf_texlayer_class_priest.png", minimal = true },
    { value = "CLASS_DEATHKNIGHT", text = "Class Fantasy | Death Knight", file = "msuf_texlayer_class_deathknight.png", minimal = true },
    { value = "CLASS_SHAMAN",      text = "Class Fantasy | Shaman",       file = "msuf_texlayer_class_shaman.png", minimal = true },
    { value = "CLASS_MAGE",        text = "Class Fantasy | Mage",         file = "msuf_texlayer_class_mage.png", minimal = true },
    { value = "CLASS_WARLOCK",     text = "Class Fantasy | Warlock",      file = "msuf_texlayer_class_warlock.png", minimal = true },
    { value = "CLASS_MONK",        text = "Class Fantasy | Monk",         file = "msuf_texlayer_class_monk.png", minimal = true },
    { value = "CLASS_DRUID",       text = "Class Fantasy | Druid",        file = "msuf_texlayer_class_druid.png", minimal = true },
    { value = "CLASS_DEMONHUNTER", text = "Class Fantasy | Demon Hunter", file = "msuf_texlayer_class_demonhunter.png", minimal = true },
    { value = "CLASS_EVOKER",      text = "Class Fantasy | Evoker",       file = "msuf_texlayer_class_evoker.png", minimal = true },
    { value = "NIGHTFORGED",         text = "No Portrait | Nightforged",           file = "msuf_texlayer_nightforged.png" },
    { value = "OBSIDIAN_VANGUARD",   text = "No Portrait | Obsidian Vanguard",     file = "msuf_texlayer_obsidian_vanguard.png" },
    { value = "ASTRAL_RUNE",         text = "No Portrait | Astral Rune",           file = "msuf_texlayer_astral_rune.png" },
    { value = "DRAGONBONE",          text = "No Portrait | Dragonbone",            file = "msuf_texlayer_dragonbone.png" },
    { value = "VERDANT_THORN",       text = "No Portrait | Verdant Thorn",         file = "msuf_texlayer_verdant_thorn.png" },
    { value = "MINIMAL_ECLIPSE",     text = "No Portrait | Minimal Eclipse",       file = "msuf_texlayer_minimal_eclipse.png" },
    { value = "MOD_SAFE_CORE",       text = "Minimal Frame | Modular Safe Core",   file = "msuf_texlayer_mod_safe_core.png", role = "FRAME" },
    { value = "MOD_CREST_TICKS",     text = "Modular Accent | Crest Ticks",        file = "msuf_texlayer_mod_crest_ticks.png", role = "ACCENT" },
    { value = "MOD_LOWER_RAIL",      text = "Modular Accent | Lower Data Rail",    file = "msuf_texlayer_mod_lower_rail.png", role = "ACCENT" },
    { value = "MOD_PORTRAIT_RING",   text = "Optional Medallion | Portrait Ring",  file = "msuf_texlayer_mod_portrait_ring.png", role = "ORNAMENT" },
}
local TEXLAYER_PACK_VALUES = { { value = "CUSTOM", text = "Select an MSUF asset..." } }
local TEXLAYER_PACK_BY_VALUE = {}
local TEXLAYER_PACK_BY_PATH = {}
for i = 1, #TEXLAYER_PACK_PRESETS do
    local preset = TEXLAYER_PACK_PRESETS[i]
    preset.path = TEXLAYER_PACK_ROOT .. preset.file
    if not preset.role then
        preset.role = (preset.value:find("^MIN_OVERLAY_") or preset.value:find("^CLASS_")) and "ACCENT" or "FRAME"
    end
    TEXLAYER_PACK_BY_VALUE[preset.value] = preset
    TEXLAYER_PACK_BY_PATH[preset.path] = preset
end
local TEXLAYER_PACK_ROLE_GROUPS = {
    { role = "FRAME", text = "Complete no-portrait frames" },
    { role = "ACCENT", text = "Optional accents and class fantasy" },
    { role = "ORNAMENT", text = "Optional medallions" },
}
for groupIndex = 1, #TEXLAYER_PACK_ROLE_GROUPS do
    local group = TEXLAYER_PACK_ROLE_GROUPS[groupIndex]
    TEXLAYER_PACK_VALUES[#TEXLAYER_PACK_VALUES + 1] = { value = "HEADER_" .. group.role, text = group.text, header = true }
    for presetIndex = 1, #TEXLAYER_PACK_PRESETS do
        local preset = TEXLAYER_PACK_PRESETS[presetIndex]
        if preset.role == group.role then
            TEXLAYER_PACK_VALUES[#TEXLAYER_PACK_VALUES + 1] = { value = preset.value, text = preset.text }
        end
    end
end

-- Eight modern moods across nine neutral bases, eight modular layouts and
-- twenty curated class-fantasy recipes produce exactly 100 looks. The catalog remains Options-only;
-- applying a look persists the same raw three-slot settings the runtime already
-- understands.
local TEXLAYER_LOOK_BASES = {
    { value = "DOUBLE_RAIL",    text = "Double Rail",    file = "msuf_texlayer_min_base_double_rail.png" },
    { value = "OPEN_BRACKET",   text = "Open Bracket",   file = "msuf_texlayer_min_base_open_bracket.png" },
    { value = "CENTER_NOTCH",   text = "Center Notch",   file = "msuf_texlayer_min_base_center_notch.png" },
    { value = "STEPPED_TECH",   text = "Stepped Tech",   file = "msuf_texlayer_min_base_stepped_tech.png" },
    { value = "ARCANE_CAPSULE", text = "Arcane Capsule", file = "msuf_texlayer_min_base_arcane_capsule.png" },
    { value = "SPLIT_HORIZON",  text = "Split Horizon",  file = "msuf_texlayer_min_base_split_horizon.png" },
    { value = "ASYM_VECTOR",    text = "Asym Vector",    file = "msuf_texlayer_min_base_asym_vector.png" },
    { value = "SHARD_CORNERS",  text = "Shard Corners",  file = "msuf_texlayer_min_base_shard_corners.png" },
    { value = "ECLIPSE_ARC",    text = "Eclipse Arc",    file = "msuf_texlayer_min_base_eclipse_arc.png" },
}
local TEXLAYER_SUPPORT_BASES = {
    { value = "HAIRLINE", text = "Hairline", file = "msuf_texlayer_min_base_hairline.png" },
}
local TEXLAYER_LOOK_MOODS = {
    { value = "CLEAN_SILVER",  text = "Clean Silver",  base = { 0.78, 0.84, 0.92 }, accent = { 0.90, 0.95, 1.00 }, overlay = "msuf_texlayer_min_overlay_micro_dots.png",   overlayAlpha = 0.58, blend = "BLEND" },
    { value = "MIDNIGHT_BLUE", text = "Midnight Blue", base = { 0.16, 0.24, 0.38 }, accent = { 0.08, 0.42, 1.00 }, overlay = "msuf_texlayer_min_overlay_energy_sweep.png", overlayAlpha = 0.72, blend = "ADD", glow = "msuf_texlayer_min_overlay_corner_glint.png", glowAlpha = 0.22 },
    { value = "VOID_VIOLET",   text = "Void Violet",   base = { 0.24, 0.19, 0.34 }, accent = { 0.58, 0.20, 1.00 }, overlay = "msuf_texlayer_min_overlay_rune_ticks.png",   overlayAlpha = 0.72, blend = "ADD", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.20 },
    { value = "ARCANE_CYAN",   text = "Arcane Cyan",   base = { 0.14, 0.31, 0.35 }, accent = { 0.05, 0.85, 1.00 }, overlay = "msuf_texlayer_min_overlay_center_sigil.png", overlayAlpha = 0.78, blend = "ADD", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.20 },
    { value = "EMBER",         text = "Ember",         base = { 0.36, 0.20, 0.14 }, accent = { 1.00, 0.24, 0.05 }, overlay = "msuf_texlayer_min_overlay_energy_sweep.png", overlayAlpha = 0.76, blend = "ADD", glow = "msuf_texlayer_min_overlay_corner_glint.png", glowAlpha = 0.24 },
    { value = "FROST",         text = "Frost",         base = { 0.30, 0.38, 0.50 }, accent = { 0.25, 0.72, 1.00 }, overlay = "msuf_texlayer_min_overlay_corner_glint.png", overlayAlpha = 0.70, blend = "ADD", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.20 },
    { value = "DAWN_GOLD",     text = "Dawn Gold",     base = { 0.42, 0.32, 0.14 }, accent = { 1.00, 0.68, 0.14 }, overlay = "msuf_texlayer_min_overlay_micro_dots.png",   overlayAlpha = 0.72, blend = "ADD", glow = "msuf_texlayer_min_overlay_center_sigil.png", glowAlpha = 0.18 },
    { value = "MONOCHROME",    text = "Monochrome",    base = { 0.30, 0.32, 0.36 }, accent = { 0.70, 0.74, 0.82 }, overlay = "msuf_texlayer_min_overlay_corner_glint.png", overlayAlpha = 0.52, blend = "BLEND" },
}
local TEXLAYER_MODULAR_LOOKS = {
    { value = "MODULAR_SAFE_BARE", text = "Modular Lab | Safe Core - Bare", swatch = { 0.72, 0.80, 0.90 },
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.72, 0.80, 0.90 }, alpha = 0.96, blend = "BLEND", level = 1 },
        } },
    { value = "MODULAR_SAFE_CREST", text = "Modular Lab | Safe Core + Crest", swatch = { 0.14, 0.70, 1.00 },
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.42, 0.52, 0.66 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_crest_ticks.png", color = { 0.14, 0.70, 1.00 }, alpha = 0.82, blend = "ADD", level = 2 },
        } },
    { value = "MODULAR_SAFE_RAIL", text = "Modular Lab | Safe Core + Data Rail", swatch = { 0.30, 0.86, 0.62 },
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.42, 0.52, 0.60 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_lower_rail.png", color = { 0.30, 0.86, 0.62 }, alpha = 0.86, blend = "ADD", level = 2 },
        } },
    { value = "MODULAR_RING_LEFT", text = "Modular Lab | Medallion Left", swatch = { 0.38, 0.70, 1.00 }, linkSize = false,
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.52, 0.62, 0.76 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_portrait_ring.png", color = { 0.38, 0.70, 1.00 }, alpha = 0.96, blend = "BLEND", level = 3, sizeMode = "HEIGHT", edgeAttach = "LEFT" },
        } },
    { value = "MODULAR_RING_RIGHT", text = "Modular Lab | Medallion Right", swatch = { 0.76, 0.46, 1.00 }, linkSize = false,
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.54, 0.50, 0.68 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_portrait_ring.png", color = { 0.76, 0.46, 1.00 }, alpha = 0.96, blend = "BLEND", level = 3, sizeMode = "HEIGHT", edgeAttach = "RIGHT", mirrorH = true },
        } },
    { value = "MODULAR_RING_CREST", text = "Modular Lab | Left Medallion + Crest", swatch = { 0.14, 0.78, 1.00 }, linkSize = false,
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.40, 0.50, 0.64 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_portrait_ring.png", color = { 0.54, 0.72, 0.94 }, alpha = 0.96, blend = "BLEND", level = 3, sizeMode = "HEIGHT", edgeAttach = "LEFT" },
            { file = "msuf_texlayer_mod_crest_ticks.png", color = { 0.14, 0.78, 1.00 }, alpha = 0.84, blend = "ADD", level = 2 },
        } },
    { value = "MODULAR_RING_RAIL", text = "Modular Lab | Right Medallion + Rail", swatch = { 1.00, 0.62, 0.20 }, linkSize = false,
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.54, 0.44, 0.34 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_portrait_ring.png", color = { 1.00, 0.62, 0.20 }, alpha = 0.96, blend = "BLEND", level = 3, sizeMode = "HEIGHT", edgeAttach = "RIGHT", mirrorH = true },
            { file = "msuf_texlayer_mod_lower_rail.png", color = { 1.00, 0.42, 0.12 }, alpha = 0.80, blend = "ADD", level = 2 },
        } },
    { value = "MODULAR_FULL_FREEDOM", text = "Modular Lab | Full Freedom", swatch = { 0.30, 0.92, 0.70 }, linkSize = false,
        specs = {
            { file = "msuf_texlayer_mod_safe_core.png", color = { 0.38, 0.50, 0.58 }, alpha = 0.96, blend = "BLEND", level = 1 },
            { file = "msuf_texlayer_mod_portrait_ring.png", color = { 0.46, 0.84, 0.92 }, alpha = 0.96, blend = "BLEND", level = 3, sizeMode = "HEIGHT", edgeAttach = "LEFT" },
            { file = "msuf_texlayer_mod_lower_rail.png", color = { 0.30, 0.92, 0.70 }, alpha = 0.84, blend = "ADD", level = 2 },
        } },
}
local TEXLAYER_CLASS_LOOKS = {
    { value = "CLASS_WARRIOR_IRON", text = "Class Fantasy | Warrior - Iron Vanguard", base = "STEPPED_TECH",
        baseColor = { 0.34, 0.24, 0.20 }, accent = { 0.86, 0.20, 0.12 }, overlay = "msuf_texlayer_class_warrior.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.18 },
    { value = "CLASS_PALADIN_OATH", text = "Class Fantasy | Paladin - Radiant Oath", base = "HAIRLINE",
        baseColor = { 0.42, 0.34, 0.20 }, accent = { 1.00, 0.78, 0.30 }, overlay = "msuf_texlayer_class_paladin.png", glow = "msuf_texlayer_min_overlay_corner_glint.png", glowAlpha = 0.24 },
    { value = "CLASS_HUNTER_WILD", text = "Class Fantasy | Hunter - Wild Hunt", base = "OPEN_BRACKET",
        baseColor = { 0.24, 0.34, 0.22 }, accent = { 0.38, 0.84, 0.26 }, overlay = "msuf_texlayer_class_hunter.png", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.18 },
    { value = "CLASS_ROGUE_NIGHT", text = "Class Fantasy | Rogue - Nightblade", base = "ASYM_VECTOR",
        baseColor = { 0.27, 0.20, 0.30 }, accent = { 0.68, 0.24, 0.80 }, overlay = "msuf_texlayer_class_rogue.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.20 },
    { value = "CLASS_PRIEST_HALO", text = "Class Fantasy | Priest - Divine Halo", base = "ECLIPSE_ARC",
        baseColor = { 0.40, 0.35, 0.46 }, accent = { 1.00, 0.84, 0.58 }, overlay = "msuf_texlayer_class_priest.png", glow = "msuf_texlayer_min_overlay_corner_glint.png", glowAlpha = 0.22 },
    { value = "CLASS_DEATHKNIGHT_FROST", text = "Class Fantasy | Death Knight - Frostbound", base = "SHARD_CORNERS",
        baseColor = { 0.28, 0.32, 0.40 }, accent = { 0.34, 0.70, 1.00 }, overlay = "msuf_texlayer_class_deathknight.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.22 },
    { value = "CLASS_SHAMAN_STORM", text = "Class Fantasy | Shaman - Stormcaller", base = "SPLIT_HORIZON",
        baseColor = { 0.27, 0.32, 0.38 }, accent = { 0.18, 0.66, 1.00 }, overlay = "msuf_texlayer_class_shaman.png", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.20 },
    { value = "CLASS_MAGE_ARCANE", text = "Class Fantasy | Mage - Arcane Orbit", base = "ARCANE_CAPSULE",
        baseColor = { 0.20, 0.28, 0.42 }, accent = { 0.18, 0.64, 1.00 }, overlay = "msuf_texlayer_class_mage.png", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.20 },
    { value = "CLASS_WARLOCK_FEL", text = "Class Fantasy | Warlock - Fel Covenant", base = "CENTER_NOTCH",
        baseColor = { 0.25, 0.18, 0.28 }, accent = { 0.42, 1.00, 0.16 }, overlay = "msuf_texlayer_class_warlock.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.22 },
    { value = "CLASS_MONK_JADE", text = "Class Fantasy | Monk - Jade Flow", base = "DOUBLE_RAIL",
        baseColor = { 0.27, 0.38, 0.32 }, accent = { 0.20, 0.90, 0.56 }, overlay = "msuf_texlayer_class_monk.png", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.18 },
    { value = "CLASS_DRUID_EMERALD", text = "Class Fantasy | Druid - Emerald Moon", base = "ECLIPSE_ARC",
        baseColor = { 0.21, 0.34, 0.24 }, accent = { 0.26, 0.86, 0.32 }, overlay = "msuf_texlayer_class_druid.png", glow = "msuf_texlayer_min_overlay_corner_glint.png", glowAlpha = 0.18 },
    { value = "CLASS_DEMONHUNTER_FEL", text = "Class Fantasy | Demon Hunter - Fel Glaive", base = "ASYM_VECTOR",
        baseColor = { 0.22, 0.18, 0.28 }, accent = { 0.52, 1.00, 0.12 }, overlay = "msuf_texlayer_class_demonhunter.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.24 },
    { value = "CLASS_EVOKER_DRACONIC", text = "Class Fantasy | Evoker - Draconic Time", base = "SHARD_CORNERS",
        baseColor = { 0.30, 0.24, 0.22 }, accent = { 0.20, 0.76, 0.96 }, overlay = "msuf_texlayer_class_evoker.png", glow = "msuf_texlayer_min_overlay_center_sigil.png", glowAlpha = 0.20 },
    { value = "CLASS_PALADIN_VERDICT", text = "Class Fantasy | Paladin - Crimson Verdict", base = "STEPPED_TECH",
        baseColor = { 0.38, 0.24, 0.18 }, accent = { 1.00, 0.38, 0.16 }, overlay = "msuf_texlayer_class_paladin.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.22 },
    { value = "CLASS_ROGUE_VENOM", text = "Class Fantasy | Rogue - Venom Veil", base = "OPEN_BRACKET",
        baseColor = { 0.22, 0.28, 0.22 }, accent = { 0.48, 0.92, 0.18 }, overlay = "msuf_texlayer_class_rogue.png", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.20 },
    { value = "CLASS_PRIEST_VOID", text = "Class Fantasy | Priest - Void Sermon", base = "CENTER_NOTCH",
        baseColor = { 0.18, 0.14, 0.27 }, accent = { 0.64, 0.26, 0.90 }, overlay = "msuf_texlayer_class_priest.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.22 },
    { value = "CLASS_DEATHKNIGHT_UNHOLY", text = "Class Fantasy | Death Knight - Unholy Runeblade", base = "SHARD_CORNERS",
        baseColor = { 0.20, 0.29, 0.23 }, accent = { 0.38, 0.90, 0.34 }, overlay = "msuf_texlayer_class_deathknight.png", glow = "msuf_texlayer_min_overlay_rune_ticks.png", glowAlpha = 0.20 },
    { value = "CLASS_SHAMAN_MAGMA", text = "Class Fantasy | Shaman - Magma Core", base = "SPLIT_HORIZON",
        baseColor = { 0.36, 0.23, 0.17 }, accent = { 1.00, 0.32, 0.06 }, overlay = "msuf_texlayer_class_shaman.png", glow = "msuf_texlayer_min_overlay_energy_sweep.png", glowAlpha = 0.24 },
    { value = "CLASS_DRUID_LUNAR", text = "Class Fantasy | Druid - Lunar Grove", base = "ARCANE_CAPSULE",
        baseColor = { 0.22, 0.25, 0.38 }, accent = { 0.48, 0.58, 1.00 }, overlay = "msuf_texlayer_class_druid.png", glow = "msuf_texlayer_min_overlay_micro_dots.png", glowAlpha = 0.20 },
    { value = "CLASS_EVOKER_BRONZE", text = "Class Fantasy | Evoker - Bronze Timeweaver", base = "HAIRLINE",
        baseColor = { 0.34, 0.27, 0.18 }, accent = { 1.00, 0.58, 0.18 }, overlay = "msuf_texlayer_class_evoker.png", glow = "msuf_texlayer_min_overlay_center_sigil.png", glowAlpha = 0.22 },
}
local TEXLAYER_LOOK_VALUES = { { value = "CUSTOM", text = "Custom layer combination" } }
local TEXLAYER_LOOK_RECIPES = {}
local TEXLAYER_LOOK_BY_VALUE = {}
local TEXLAYER_LOOK_BASE_BY_VALUE = {}
local function AddLookRecipe(recipe, tooltip)
    TEXLAYER_LOOK_RECIPES[#TEXLAYER_LOOK_RECIPES + 1] = recipe
    TEXLAYER_LOOK_BY_VALUE[recipe.value] = recipe
    TEXLAYER_LOOK_VALUES[#TEXLAYER_LOOK_VALUES + 1] = {
        value = recipe.value,
        text = recipe.text,
        swatchColor = recipe.swatch or (recipe.mood and recipe.mood.accent) or { 0.70, 0.78, 0.90 },
        tooltip = tooltip or recipe.tooltip or (recipe.mood and ((recipe.mood.glowPath and "Three" or "Two") .. " coordinated static texture layers; fully editable after applying."))
            or "A no-portrait frame with optional independently movable modular layers.",
    }
end
for i = 1, #TEXLAYER_SUPPORT_BASES do
    local base = TEXLAYER_SUPPORT_BASES[i]
    base.path = TEXLAYER_PACK_ROOT .. base.file
    TEXLAYER_LOOK_BASE_BY_VALUE[base.value] = base
end
for baseIndex = 1, #TEXLAYER_LOOK_BASES do
    local base = TEXLAYER_LOOK_BASES[baseIndex]
    base.path = TEXLAYER_PACK_ROOT .. base.file
    TEXLAYER_LOOK_BASE_BY_VALUE[base.value] = base
    TEXLAYER_LOOK_VALUES[#TEXLAYER_LOOK_VALUES + 1] = { value = "HEADER_" .. base.value, text = base.text, header = true }
    for moodIndex = 1, #TEXLAYER_LOOK_MOODS do
        local mood = TEXLAYER_LOOK_MOODS[moodIndex]
        mood.overlayPath = mood.overlayPath or (TEXLAYER_PACK_ROOT .. mood.overlay)
        mood.glowPath = mood.glow and (mood.glowPath or (TEXLAYER_PACK_ROOT .. mood.glow)) or nil
        local value = base.value .. "__" .. mood.value
        local recipe = { value = value, text = base.text .. " | " .. mood.text, base = base, mood = mood }
        AddLookRecipe(recipe)
    end
end
TEXLAYER_LOOK_VALUES[#TEXLAYER_LOOK_VALUES + 1] = { value = "HEADER_MODULAR_LAB", text = "Modular Lab", header = true }
for i = 1, #TEXLAYER_MODULAR_LOOKS do
    AddLookRecipe(TEXLAYER_MODULAR_LOOKS[i])
end
TEXLAYER_LOOK_VALUES[#TEXLAYER_LOOK_VALUES + 1] = { value = "HEADER_CLASS_FANTASY", text = "Class Fantasy", header = true }
for i = 1, #TEXLAYER_CLASS_LOOKS do
    local look = TEXLAYER_CLASS_LOOKS[i]
    local base = TEXLAYER_LOOK_BASE_BY_VALUE[look.base]
    local mood = {
        base = look.baseColor,
        accent = look.accent,
        overlayPath = TEXLAYER_PACK_ROOT .. look.overlay,
        overlayAlpha = look.overlayAlpha or 0.78,
        blend = look.blend or "ADD",
        glowPath = look.glow and (TEXLAYER_PACK_ROOT .. look.glow) or nil,
        glowAlpha = look.glowAlpha or 0.20,
    }
    AddLookRecipe({ value = look.value, text = look.text, base = base, mood = mood },
        "Original class-fantasy accent with three responsive static layers; no official class icon is copied.")
end
local function BuildTextureLayer(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local SetString = UP.SetString
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    local Call = UP.Call
    local ReviewedMeta = UP.ReviewedMeta
    if not (ReadBool and SetBool and ReadNumber and SetNumber and SetString and SetControlEnabled and GetConf and Call and ReviewedMeta) then return end

    M.unitTexLayerSlot = M.unitTexLayerSlot or {}
    M.unitTexLayerTab = M.unitTexLayerTab or {}
    local function CurrentSlot()
        local slot = tonumber(M.unitTexLayerSlot[unit]) or 1
        if slot < 1 or slot > #SLOT_PREFIXES then slot = 1 end
        return slot
    end
    local function Key(base)
        return SLOT_PREFIXES[CurrentSlot()] .. base
    end
    local function RefreshLayer()
        Call("MSUF_RefreshUnitTextureLayers", unit)
    end

    local sec = builder:CollapsibleSection("texture_layer", "Texture Layer", TEXLAYER_SECTION_H, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local colGap = 16
    local colW = floor((innerW - 32 - colGap) / 2)
    local colX = 16 + colW + colGap

    local generalCard = W.ControlCard(sec, "General", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local placementCard = W.ControlCard(sec, "Placement", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local styleCard = W.ControlCard(sec, "Style", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local visibilityCard = W.ControlCard(sec, "Visibility", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local cardsByTab = { general = generalCard, placement = placementCard, style = styleCard, visibility = visibilityCard }

    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(styleCard, function()
            local slotIds = { "texture_layer", "texture_layer2", "texture_layer3" }
            local slotId = slotIds[CurrentSlot()] or "texture_layer"
            local refs = { slotId .. ".color" }
            if GetConf(unit)[Key("GradientEnabled")] == true then
                refs[#refs + 1] = slotId .. ".gradient"
            end
            return refs
        end, {
            title = "Texture Layer Colors",
            note = "These colors are shared from the Colors page.",
            historySource = "menu:unit-texture-layer-colors",
            context = function() return { unit = unit } end,
        })
    end

    local dependentControls = {}
    local function Track(control)
        dependentControls[#dependentControls + 1] = control
        return control
    end
    local function LayerMeta(base, path, step)
        local meta = ReviewedMeta(ctx, "texture_layer." .. (path or base), "setting", "dynamic",
            "This control edits the texture-layer slot selected in the accordion's slot bar.")
        local keys = {}
        for i = 1, #SLOT_PREFIXES do keys[i] = tostring(unit) .. "." .. SLOT_PREFIXES[i] .. base end
        meta.assistantSettingKeys = keys
        if step and meta then meta.step, meta.roundStep = step, true end
        return meta
    end
    local function PackPresetMeta()
        return ReviewedMeta(ctx, "texture_layer.design_preset", "setting", "compound",
            "Frames work alone without a portrait. Accents and medallions are optional layers with role-aware sizing; every saved value remains editable.")
    end
    local function SourceModeMeta()
        local meta = ReviewedMeta(ctx, "texture_layer.source_mode", "setting", "dynamic",
            "Chooses the one active texture source for the selected layer, so an old custom path can never silently override SharedMedia.")
        local keys = {}
        for i = 1, #SLOT_PREFIXES do keys[i] = tostring(unit) .. "." .. SLOT_PREFIXES[i] .. "SourceMode" end
        meta.assistantSettingKeys = keys
        return meta
    end
    local function LayeredLookMeta()
        return ReviewedMeta(ctx, "texture_layer.layered_look", "setting", "compound",
            "A layered look coordinates up to three static texture slots from a 100-look catalog. Modular looks keep the medallion optional and independently sizeable.")
    end
    local function LinkedGeometryMeta()
        return ReviewedMeta(ctx, "texture_layer.link_geometry", "setting", "compound",
            "Moves every enabled texture-layer slot by the same delta, preserving relative placement such as a medallion on the frame edge.")
    end
    local function LinkedSizeMeta()
        return ReviewedMeta(ctx, "texture_layer.link_size", "setting", "compound",
            "Applies sizing-mode and manual-size changes to every enabled layer. Modular medallion looks disable this so square ornaments keep their shape.")
    end
    local function CurrentPackPreset()
        local path = tostring(GetConf(unit)[Key("CustomTexturePath")] or "")
        local preset = TEXLAYER_PACK_BY_PATH[path]
        return preset and preset.value or "CUSTOM"
    end
    local function CurrentSourceMode()
        local conf = GetConf(unit)
        local mode = tostring(conf[Key("SourceMode")] or "")
        if mode == "PACK" or mode == "SHAREDMEDIA" or mode == "CUSTOM" then return mode end
        local path = tostring(conf[Key("CustomTexturePath")] or "")
        if TEXLAYER_PACK_BY_PATH[path] then return "PACK" end
        if path ~= "" then return "CUSTOM" end
        return "SHAREDMEDIA"
    end
    local function ApplyPackPreset(value)
        local preset = TEXLAYER_PACK_BY_VALUE[value]
        if not preset then return false end
        local prefix = SLOT_PREFIXES[CurrentSlot()]
        local conf = GetConf(unit)
        local frameW = max(40, tonumber(conf.width) or 180)
        local frameH = max(10, tonumber(conf.height) or 30)
        local fittedHeight = floor(min(220, max(48, (frameH + 10) / 0.30)) + 0.5)
        local fittedWidth = floor(min(600, max(72, (frameW + 20) / 0.82)) + 0.5)
        local sizeMode = preset.role == "ORNAMENT" and "HEIGHT" or "FRAME"
        local height = fittedHeight
        local width = sizeMode == "HEIGHT" and fittedHeight or fittedWidth

        local function Write()
            local changed = false
            local function Assign(suffix, nextValue)
                local key = prefix .. suffix
                if conf[key] ~= nextValue then
                    conf[key] = nextValue
                    changed = true
                end
            end
            Assign("Enabled", true)
            Assign("SourceMode", "PACK")
            Assign("Texture", "")
            Assign("CustomTexturePath", preset.path)
            Assign("Alpha", 1)
            Assign("FollowFrameAlpha", true)
            Assign("Strata", "AUTO")
            Assign("Level", 1)
            Assign("AnchorTarget", "FRAME")
            Assign("Anchor", "CENTER")
            Assign("OffsetX", 0)
            Assign("OffsetY", 0)
            Assign("SizeMode", sizeMode)
            Assign("EdgeAttach", preset.role == "ORNAMENT" and "LEFT" or "FREE")
            Assign("ResponsiveSize", true)
            Assign("Width", width)
            Assign("Height", height)
            Assign("ColorMode", "CUSTOM")
            Assign("ColorR", 1)
            Assign("ColorG", 1)
            Assign("ColorB", 1)
            Assign("GradientEnabled", false)
            Assign("BlendMode", "BLEND")
            Assign("MirrorH", false)
            Assign("MirrorV", false)
            Assign("EdgeSoftness", 0)
            Assign("Visibility", "ALWAYS")
            Assign("RoundedClip", false)
            if not changed then return false end
            if type(M.RequestUnitApply) == "function" then
                M.RequestUnitApply(unit, "MSUF2_TEXLAYER_PACK_PRESET", { preview = true, history = false })
            end
            return true
        end
        local changed
        if type(M.RunWithHistory) == "function" then
            changed = M.RunWithHistory("Texture design: " .. preset.text,
                "unit:texture-layer-preset:" .. tostring(unit) .. ":" .. tostring(CurrentSlot()), Write)
        else
            changed = Write()
        end
        if changed ~= false then
            RefreshLayer()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_PACK_PRESET")
        end
        return changed
    end
    local function NearlyEqual(a, b)
        return abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= 0.0005
    end
    local function SlotMatches(conf, prefix, spec)
        local enabled = conf[prefix .. "Enabled"] == true
        if enabled ~= (spec ~= nil) then return false end
        if not spec then return true end
        if tostring(conf[prefix .. "CustomTexturePath"] or "") ~= spec.path then return false end
        if tostring(conf[prefix .. "SourceMode"] or "") ~= "PACK" then return false end
        if tostring(conf[prefix .. "Texture"] or "") ~= "" then return false end
        local sizeMode = tostring(conf[prefix .. "SizeMode"] or "")
        if sizeMode ~= "FRAME" and sizeMode ~= "HEIGHT" and sizeMode ~= "MANUAL" then
            sizeMode = conf[prefix .. "ResponsiveSize"] == true and "FRAME" or "MANUAL"
        end
        if sizeMode ~= (spec.sizeMode or "FRAME") then return false end
        if tostring(conf[prefix .. "EdgeAttach"] or "FREE") ~= (spec.edgeAttach or "FREE") then return false end
        if tostring(conf[prefix .. "Anchor"] or "CENTER") ~= (spec.anchor or "CENTER") then return false end
        if not NearlyEqual(conf[prefix .. "OffsetX"], spec.offsetX or 0) then return false end
        if not NearlyEqual(conf[prefix .. "OffsetY"], spec.offsetY or 0) then return false end
        if (conf[prefix .. "MirrorH"] == true) ~= (spec.mirrorH == true) then return false end
        if (conf[prefix .. "MirrorV"] == true) ~= (spec.mirrorV == true) then return false end
        if not NearlyEqual(conf[prefix .. "EdgeSoftness"], 0) then return false end
        if tostring(conf[prefix .. "ColorMode"] or "CUSTOM") ~= "CUSTOM" then return false end
        if tostring(conf[prefix .. "BlendMode"] or "BLEND") ~= spec.blend then return false end
        if tostring(conf[prefix .. "Visibility"] or "ALWAYS") ~= "ALWAYS" then return false end
        if conf[prefix .. "GradientEnabled"] == true or conf[prefix .. "RoundedClip"] == true then return false end
        if not NearlyEqual(conf[prefix .. "Alpha"] == nil and 1 or conf[prefix .. "Alpha"], spec.alpha) then return false end
        return NearlyEqual(conf[prefix .. "ColorR"] == nil and 1 or conf[prefix .. "ColorR"], spec.color[1])
            and NearlyEqual(conf[prefix .. "ColorG"] == nil and 1 or conf[prefix .. "ColorG"], spec.color[2])
            and NearlyEqual(conf[prefix .. "ColorB"] == nil and 1 or conf[prefix .. "ColorB"], spec.color[3])
    end
    local function RecipeSpecs(recipe)
        if recipe.specs then
            local specs = {}
            for slot = 1, #SLOT_PREFIXES do
                local source = recipe.specs[slot]
                if source then
                    local spec = {}
                    for key, value in pairs(source) do spec[key] = value end
                    spec.path = spec.path or (TEXLAYER_PACK_ROOT .. spec.file)
                    spec.alpha = spec.alpha or 1
                    spec.color = spec.color or { 1, 1, 1 }
                    spec.blend = spec.blend or "BLEND"
                    spec.level = spec.level or slot
                    specs[slot] = spec
                end
            end
            return specs
        end
        local mood = recipe.mood
        return {
            { path = recipe.base.path, alpha = 0.95, color = mood.base, blend = "BLEND", level = 1 },
            { path = mood.overlayPath, alpha = mood.overlayAlpha, color = mood.accent, blend = mood.blend, level = 2 },
            mood.glowPath and { path = mood.glowPath, alpha = mood.glowAlpha, color = mood.accent, blend = "ADD", level = 3 } or nil,
        }
    end
    local function CurrentLayeredLook()
        local conf = GetConf(unit)
        for i = 1, #TEXLAYER_LOOK_RECIPES do
            local recipe = TEXLAYER_LOOK_RECIPES[i]
            local specs = RecipeSpecs(recipe)
            local match = true
            for slot = 1, #SLOT_PREFIXES do
                if not SlotMatches(conf, SLOT_PREFIXES[slot], specs[slot]) then match = false break end
            end
            if match then return recipe.value end
        end
        return "CUSTOM"
    end
    local function ApplyLayeredLook(value)
        local recipe = TEXLAYER_LOOK_BY_VALUE[value]
        if not recipe then return false end
        local conf = GetConf(unit)
        local frameW = max(40, tonumber(conf.width) or 180)
        local frameH = max(10, tonumber(conf.height) or 30)
        local width = floor(min(600, max(72, (frameW + 20) / 0.82)) + 0.5)
        local height = floor(min(220, max(48, (frameH + 10) / 0.30)) + 0.5)
        local specs = RecipeSpecs(recipe)

        local function Write()
            local changed = false
            local function Assign(prefix, suffix, nextValue)
                local key = prefix .. suffix
                if conf[key] ~= nextValue then
                    conf[key] = nextValue
                    changed = true
                end
            end
            if conf.texLayerLinkGeometry ~= true then
                conf.texLayerLinkGeometry = true
                changed = true
            end
            local linkSize = recipe.linkSize ~= false
            if conf.texLayerLinkSize ~= linkSize then
                conf.texLayerLinkSize = linkSize
                changed = true
            end
            local function StampSlot(slot, spec)
                local prefix = SLOT_PREFIXES[slot]
                local color = spec and spec.color or { 1, 1, 1 }
                local sizeMode = spec and (spec.sizeMode or "FRAME") or "FRAME"
                Assign(prefix, "Enabled", spec ~= nil)
                Assign(prefix, "SourceMode", "PACK")
                Assign(prefix, "Texture", "")
                Assign(prefix, "CustomTexturePath", spec and spec.path or "")
                Assign(prefix, "Alpha", spec and spec.alpha or 1)
                Assign(prefix, "FollowFrameAlpha", true)
                Assign(prefix, "Strata", "AUTO")
                Assign(prefix, "Level", spec and spec.level or slot)
                Assign(prefix, "AnchorTarget", "FRAME")
                Assign(prefix, "Anchor", spec and (spec.anchor or "CENTER") or "CENTER")
                Assign(prefix, "OffsetX", spec and (spec.offsetX or 0) or 0)
                Assign(prefix, "OffsetY", spec and (spec.offsetY or 0) or 0)
                Assign(prefix, "SizeMode", sizeMode)
                Assign(prefix, "EdgeAttach", spec and (spec.edgeAttach or "FREE") or "FREE")
                Assign(prefix, "ResponsiveSize", sizeMode ~= "MANUAL")
                Assign(prefix, "Width", sizeMode == "HEIGHT" and height or width)
                Assign(prefix, "Height", height)
                Assign(prefix, "ColorMode", "CUSTOM")
                Assign(prefix, "ColorR", color[1])
                Assign(prefix, "ColorG", color[2])
                Assign(prefix, "ColorB", color[3])
                Assign(prefix, "GradientEnabled", false)
                Assign(prefix, "BlendMode", spec and spec.blend or "BLEND")
                Assign(prefix, "MirrorH", spec and spec.mirrorH == true or false)
                Assign(prefix, "MirrorV", spec and spec.mirrorV == true or false)
                Assign(prefix, "EdgeSoftness", 0)
                Assign(prefix, "Visibility", "ALWAYS")
                Assign(prefix, "RoundedClip", false)
            end
            for slot = 1, #SLOT_PREFIXES do StampSlot(slot, specs[slot]) end
            if not changed then return false end
            if type(M.RequestUnitApply) == "function" then
                M.RequestUnitApply(unit, "MSUF2_TEXLAYER_LAYERED_LOOK", { preview = true, history = false })
            end
            return true
        end
        local changed
        if type(M.RunWithHistory) == "function" then
            changed = M.RunWithHistory("Layered texture look: " .. recipe.text,
                "unit:texture-layer-look:" .. tostring(unit), Write)
        else
            changed = Write()
        end
        if changed ~= false then
            RefreshLayer()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_LAYERED_LOOK")
        end
        return changed
    end
    local function SetLinkedGeometry(base, nextValue, linkMode)
        local conf = GetConf(unit)
        local linkKey = linkMode == "size" and "texLayerLinkSize" or "texLayerLinkGeometry"
        if conf[linkKey] ~= true then return false end
        local changed = false
        local delta
        if linkMode == "move" and (base == "OffsetX" or base == "OffsetY") then
            local selectedKey = SLOT_PREFIXES[CurrentSlot()] .. base
            delta = (tonumber(nextValue) or 0) - (tonumber(conf[selectedKey]) or 0)
        end
        for i = 1, #SLOT_PREFIXES do
            local prefix = SLOT_PREFIXES[i]
            if conf[prefix .. "Enabled"] == true then
                local key = prefix .. base
                local linkedValue = delta and ((tonumber(conf[key]) or 0) + delta) or nextValue
                if conf[key] ~= linkedValue then
                    conf[key] = linkedValue
                    changed = true
                end
            end
        end
        if changed and type(M.RequestUnitApply) == "function" then
            M.RequestUnitApply(unit, "MSUF2_TEXLAYER_LINKED_GEOMETRY", { preview = true })
        end
        return true
    end
    local function BindLayerToggle(parent, label, x, y, width, base, default, after, linkMode)
        local control = W.ToggleAt(parent, label, x, y, width)
        M.BindBoolWidget(ctx, control,
            function() return ReadBool(unit, Key(base), default) end,
            function(v)
                if not (linkMode and SetLinkedGeometry(base, v == true, linkMode)) then
                    SetBool(unit, Key(base), v, "MSUF2_TEXLAYER", { preview = true })
                end
                RefreshLayer()
                if after then after() end
            end,
            LayerMeta(base))
        return control
    end
    local function BindLayerSlider(parent, label, x, y, width, minV, maxV, step, base, default, percent, linkMode)
        local control = W.Slider(parent, label, minV, maxV, step, width - 58)
        if percent then
            M.UsePercentInput(control)
        elseif control.SetValueFormatter then
            control:SetValueFormatter(function(v) return tostring(floor((tonumber(v) or 0) + 0.5)) end)
        end
        M.BindNumberWidget(ctx, control,
            function() return ReadNumber(unit, Key(base), default) end,
            function(v)
                if not (linkMode and SetLinkedGeometry(base, tonumber(v) or default, linkMode)) then
                    SetNumber(unit, Key(base), v, "MSUF2_TEXLAYER", { preview = true })
                end
                RefreshLayer()
            end,
            default,
            LayerMeta(base, nil, percent and nil or step))
        W.MoveWidget(control, parent, x, y, width - 58, "LEFT")
        return control
    end
    local function BindLayerDropdown(parent, label, x, y, width, values, base, default, linkMode)
        local control = W.Dropdown(parent, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local value = GetConf(unit)[Key(base)]
                if value == nil or value == "" then value = default end
                return value
            end,
            function(v)
                local nextValue = v or default
                if not (linkMode and SetLinkedGeometry(base, nextValue, linkMode)) then
                    SetString(unit, Key(base), nextValue, "MSUF2_TEXLAYER", { preview = true })
                end
                RefreshLayer()
            end,
            LayerMeta(base))
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end

    -- General: enable, art sources, layering.
    BindLayerToggle(generalCard, "Enable Texture Layer", 16, -54, colW - 16, "Enabled", false, function()
        M.RequestRefresh(ctx, "MSUF2_TEXLAYER_ENABLE")
    end)
    local layeredLook = W.Dropdown(generalCard, "Complete design (100 looks / all 3 layers)", TEXLAYER_LOOK_VALUES, colW - 16)
    M.BindDropdownWidget(ctx, layeredLook,
        CurrentLayeredLook,
        ApplyLayeredLook,
        LayeredLookMeta())
    W.MoveWidget(layeredLook, generalCard, 16, -114, colW - 16, "LEFT")

    local RefreshSourceControls
    local sourceMode = W.Dropdown(generalCard, "Active source for this layer", TEXLAYER_SOURCE_MODES, colW - 16)
    M.BindDropdownWidget(ctx, sourceMode,
        CurrentSourceMode,
        function(v)
            local nextMode = v == "PACK" and "PACK" or (v == "CUSTOM" and "CUSTOM" or "SHAREDMEDIA")
            SetString(unit, Key("SourceMode"), nextMode, "MSUF2_TEXLAYER_SOURCE", { preview = true })
            RefreshLayer()
            if RefreshSourceControls then RefreshSourceControls() end
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_SOURCE")
        end,
        SourceModeMeta())
    W.MoveWidget(sourceMode, generalCard, 16, -190, colW - 16, "LEFT")

    local packPreset = W.Dropdown(generalCard, "MSUF asset (frames / optional layers)", TEXLAYER_PACK_VALUES, colW - 16)
    M.BindDropdownWidget(ctx, packPreset,
        CurrentPackPreset,
        ApplyPackPreset,
        PackPresetMeta())
    W.MoveWidget(packPreset, generalCard, 16, -266, colW - 16, "LEFT")

    local sharedMedia = W.Dropdown(generalCard, "SharedMedia texture", function() return M.StatusBarTextureItems("Use bar texture") end, colW - 16)
    M.BindDropdownWidget(ctx, sharedMedia,
        function() return tostring(GetConf(unit)[Key("Texture")] or "") end,
        function(v)
            SetString(unit, Key("SourceMode"), "SHAREDMEDIA", "MSUF2_TEXLAYER_SOURCE", { preview = true })
            SetString(unit, Key("Texture"), v or "", "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        LayerMeta("Texture"))
    W.MoveWidget(sharedMedia, generalCard, 16, -266, colW - 16, "LEFT")
    Track(sharedMedia)

    Track(BindLayerSlider(generalCard, "Layer (0-30)", colX, -62, colW, 0, 30, 1, "Level", 1))
    local customPath = W.TextInput(generalCard, "Custom file path", colW - 16)
    M.BindTextInput(ctx, customPath,
        function() return tostring(GetConf(unit)[Key("CustomTexturePath")] or "") end,
        function(v)
            SetString(unit, Key("SourceMode"), "CUSTOM", "MSUF2_TEXLAYER_SOURCE", { preview = true })
            SetString(unit, Key("CustomTexturePath"), v or "", "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_CUSTOM_PATH")
        end,
        true,
        LayerMeta("CustomTexturePath"))
    W.MoveWidget(customPath, generalCard, 16, -266, colW - 16, "LEFT")
    Track(customPath)
    Track(BindLayerDropdown(generalCard, "Frame strata", colX, -140, colW - 16, TEXLAYER_STRATA, "Strata", "AUTO"))
    W.LabelAt(generalCard, "Frames work alone; accents and medallions are optional.", colX, -208, colW - 16, "GameFontNormalSmall", T.colors and T.colors.muted)
    W.LabelAt(generalCard, "Active source edits only the selected layer.", colX, -230, colW - 16, "GameFontNormalSmall", T.colors and T.colors.muted)
    RefreshSourceControls = function()
        local mode = CurrentSourceMode()
        W.SetControlShown(packPreset, mode == "PACK")
        W.SetControlShown(sharedMedia, mode == "SHAREDMEDIA")
        W.SetControlShown(customPath, mode == "CUSTOM")
    end
    RefreshSourceControls()

    -- Placement: each slot keeps its own anchor/edge relationship. Moving can
    -- stay linked by delta, while sizing is a separate opt-in link so square
    -- ornaments never get stretched with full-frame art.
    Track(BindLayerDropdown(placementCard, "Anchor to", 16, -54, colW - 16, TEXLAYER_ANCHOR_TARGETS, "AnchorTarget", "FRAME"))
    Track(BindLayerDropdown(placementCard, "Anchor", 16, -130, colW - 16, TEXLAYER_ANCHORS, "Anchor", "CENTER"))
    local manualSizeControls = {}
    local function CurrentSizeMode()
        local conf = GetConf(unit)
        local mode = tostring(conf[Key("SizeMode")] or "")
        if mode == "FRAME" or mode == "HEIGHT" or mode == "MANUAL" then return mode end
        return conf[Key("ResponsiveSize")] == true and "FRAME" or "MANUAL"
    end
    local function RefreshSizeControls()
        local manual = ReadBool(unit, Key("Enabled"), false) and CurrentSizeMode() == "MANUAL"
        for i = 1, #manualSizeControls do SetControlEnabled(manualSizeControls[i], manual) end
    end
    local sizeMode = W.Dropdown(placementCard, "Sizing mode", TEXLAYER_SIZE_MODES, colW - 16)
    M.BindDropdownWidget(ctx, sizeMode,
        CurrentSizeMode,
        function(v)
            local nextMode = v == "HEIGHT" and "HEIGHT" or (v == "MANUAL" and "MANUAL" or "FRAME")
            if not SetLinkedGeometry("SizeMode", nextMode, "size") then
                SetString(unit, Key("SizeMode"), nextMode, "MSUF2_TEXLAYER_SIZE_MODE", { preview = true })
            end
            if not SetLinkedGeometry("ResponsiveSize", nextMode ~= "MANUAL", "size") then
                SetBool(unit, Key("ResponsiveSize"), nextMode ~= "MANUAL", "MSUF2_TEXLAYER_SIZE_MODE", { preview = true })
            end
            RefreshLayer()
            RefreshSizeControls()
        end,
        LayerMeta("SizeMode"))
    W.MoveWidget(sizeMode, placementCard, 16, -206, colW - 16, "LEFT")
    Track(sizeMode)
    Track(BindLayerDropdown(placementCard, "Edge attachment", 16, -282, colW - 16, TEXLAYER_EDGE_ATTACH, "EdgeAttach", "FREE"))
    Track(BindLayerSlider(placementCard, "Offset X", colX, -62, colW, -300, 300, 1, "OffsetX", 0, nil, "move"))
    Track(BindLayerSlider(placementCard, "Offset Y", colX, -120, colW, -300, 300, 1, "OffsetY", 0, nil, "move"))
    local widthControl = Track(BindLayerSlider(placementCard, "Manual width", colX, -178, colW, 0, 600, 1, "Width", 0, nil, "size"))
    manualSizeControls[#manualSizeControls + 1] = widthControl
    local heightControl = Track(BindLayerSlider(placementCard, "Manual height", colX, -236, colW, 1, 220, 1, "Height", 16, nil, "size"))
    manualSizeControls[#manualSizeControls + 1] = heightControl
    local linkedGeometry = W.ToggleAt(placementCard, "Move enabled layers together", colX, -298, colW - 16)
    M.BindBoolWidget(ctx, linkedGeometry,
        function() return ReadBool(unit, "texLayerLinkGeometry", false) end,
        function(v)
            SetBool(unit, "texLayerLinkGeometry", v, "MSUF2_TEXLAYER_LINK_GEOMETRY", { preview = true })
            RefreshLayer()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_LINK_GEOMETRY")
        end,
        LinkedGeometryMeta())
    local linkedSize = W.ToggleAt(placementCard, "Resize enabled layers together", colX, -334, colW - 16)
    M.BindBoolWidget(ctx, linkedSize,
        function() return ReadBool(unit, "texLayerLinkSize", false) end,
        function(v)
            SetBool(unit, "texLayerLinkSize", v, "MSUF2_TEXLAYER_LINK_SIZE", { preview = true })
            RefreshLayer()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_LINK_SIZE")
        end,
        LinkedSizeMeta())
    W.LabelAt(placementCard, "Preview dragging preserves every layer's relative offset.", colX, -372, colW - 16, "GameFontNormalSmall", T.colors and T.colors.muted)
    RefreshSizeControls()

    -- Style: color mode, gradient with a Bars-style direction D-pad, blend,
    -- mirroring, opacity and a four-edge feather mask. Colors themselves live on
    -- the Colors page and behind this card's three-dot context shortcut.
    local padButtons = {}
    local pad
    local function DirectionActive(value)
        return ReadBool(unit, Key(PAD_DIRECTION_SUFFIXES[value]), value == "RIGHT")
    end
    local function AnyDirectionActive()
        return DirectionActive("UP") or DirectionActive("LEFT") or DirectionActive("RIGHT") or DirectionActive("DOWN")
    end
    local function RefreshGradientControls()
        local on = ReadBool(unit, Key("Enabled"), false) and ReadBool(unit, Key("GradientEnabled"), false)
        if pad and pad.SetAlpha then pad:SetAlpha(on and 1 or 0.45) end
        for value, btn in pairs(padButtons) do
            if btn.SetActive then btn:SetActive(DirectionActive(value)) end
            SetControlEnabled(btn, on)
        end
    end
    local colorMode = W.Dropdown(styleCard, "Color mode", TEXLAYER_COLOR_MODES, colW - 16)
    M.BindDropdownWidget(ctx, colorMode,
        function() return GetConf(unit)[Key("ColorMode")] == "CLASS" and "CLASS" or "CUSTOM" end,
        function(v)
            SetString(unit, Key("ColorMode"), v == "CLASS" and "CLASS" or "CUSTOM", "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        LayerMeta("ColorMode"))
    W.MoveWidget(colorMode, styleCard, 16, -54, colW - 16, "LEFT")
    Track(colorMode)
    Track(BindLayerToggle(styleCard, "Gradient", 16, -122, colW - 16, "GradientEnabled", false, RefreshGradientControls))
    W.LabelAt(styleCard, "Direction", 16, -156, colW - 16, "GameFontNormalSmall", T.colors and T.colors.accent)
    local padW, padH = 104, 78
    local padButtonW, padButtonH = 22, 18
    pad = T.Panel(styleCard, nil, (T.colors and T.colors.panel2) or { 0.014, 0.038, 0.072, 0.55 }, T.colors and T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", styleCard, "TOPLEFT", 16, -178)
    pad:SetSize(padW, padH)
    local padCenter = pad:CreateTexture(nil, "ARTWORK")
    padCenter:SetPoint("CENTER", pad, "CENTER", 0, 0)
    padCenter:SetSize(10, 10)
    local padCenterColor = (T.colors and T.colors.coreRim) or { 0.043, 0.096, 0.150 }
    padCenter:SetColorTexture(padCenterColor[1], padCenterColor[2], padCenterColor[3], 0.95)
    local function PadButton(text, value, x, buttonY)
        local btn = T.Button(pad, text, padButtonW, padButtonH)
        btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, buttonY)
        if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
        btn:SetScript("OnClick", function()
            local base = PAD_DIRECTION_SUFFIXES[value]
            SetBool(unit, Key(base), not DirectionActive(value), "MSUF2_TEXLAYER", { preview = true })
            -- Never leave the gradient without an edge: re-enable the clicked
            -- direction when it was the last active one (Bars pad behavior).
            if not AnyDirectionActive() then
                SetBool(unit, Key(base), true, "MSUF2_TEXLAYER", { preview = true })
            end
            RefreshLayer()
            RefreshGradientControls()
        end)
        if UP.RegisterControl then
            UP.RegisterControl(btn, ctx, "texture_layer.gradient_direction." .. value, "Gradient direction", "button", "ephemeral")
        end
        padButtons[value] = btn
        return btn
    end
    local padCenterX = (padW - padButtonW) * 0.5
    local padCenterY = (padH - padButtonH) * 0.5
    local padSideOffset = 23
    PadButton("^", "UP", padCenterX, -(padCenterY - padSideOffset))
    PadButton("<", "LEFT", padCenterX - padSideOffset, -padCenterY)
    PadButton(">", "RIGHT", padCenterX + padSideOffset, -padCenterY)
    PadButton("v", "DOWN", padCenterX, -(padCenterY + padSideOffset))
    Track(BindLayerSlider(styleCard, "Opacity", colX, -62, colW, 0, 1, 0.05, "Alpha", 1, true))
    local blend = W.ToggleAt(styleCard, "Additive glow", colX, -122, colW - 16)
    M.BindBoolWidget(ctx, blend,
        function() return GetConf(unit)[Key("BlendMode")] == "ADD" end,
        function(v)
            SetString(unit, Key("BlendMode"), v and "ADD" or "BLEND", "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        LayerMeta("BlendMode"))
    Track(blend)
    Track(BindLayerToggle(styleCard, "Mirror horizontally", colX, -168, colW - 16, "MirrorH", false))
    Track(BindLayerToggle(styleCard, "Mirror vertically", colX, -214, colW - 16, "MirrorV", false))
    Track(BindLayerSlider(styleCard, "Edge softness", colX, -272, colW, 0, 0.30, 0.02, "EdgeSoftness", 0, true))
    W.LabelAt(styleCard, "Fades all four outer edges; 0% keeps the original texture.", colX, -322,
        colW - 16, "GameFontNormalSmall", T.colors and T.colors.muted)

    -- Visibility: alpha inheritance, combat gating, rounded clipping.
    Track(BindLayerToggle(visibilityCard, "Follow frame transparency", 16, -54, colW - 16, "FollowFrameAlpha", true))
    Track(BindLayerDropdown(visibilityCard, "Show", 16, -114, colW - 16, TEXLAYER_VISIBILITY, "Visibility", "ALWAYS"))
    Track(BindLayerToggle(visibilityCard, "Clip to rounded frame", colX, -62, colW - 16, "RoundedClip", false))

    -- Slot + category bars. Both are menu-session state, never persisted.
    local function ApplyTab()
        local tab = M.unitTexLayerTab[unit]
        if not cardsByTab[tab] then tab = "general" end
        for key, card in pairs(cardsByTab) do
            W.SetControlShown(card, key == tab)
        end
    end
    local slotValues = {
        { value = 1, text = "Layer 1" },
        { value = 2, text = "Layer 2" },
        { value = 3, text = "Layer 3" },
    }
    local slotBar = W.ScopeOverrideBar(ctx, sec, {
        values = slotValues,
        width = sectionW,
        label = "Editing:",
        labelX = leftX,
        labelWidth = 64,
        centerY = -52,
        getValue = function() return CurrentSlot() end,
        setValue = function(value)
            M.unitTexLayerSlot[unit] = tonumber(value) or 1
            RefreshGradientControls()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_SLOT")
        end,
    })
    if UP.RegisterControl then
        UP.RegisterControl(slotBar, ctx, "texture_layer.slot_selector", "Editing", "segment", "ephemeral")
    end
    local tabValues = {}
    for i = 1, #TEXLAYER_TABS do
        tabValues[i] = { value = TEXLAYER_TABS[i], text = TEXLAYER_TAB_TEXTS[TEXLAYER_TABS[i]] }
    end
    local tabBar = W.ScopeOverrideBar(ctx, sec, {
        values = tabValues,
        width = sectionW,
        label = "Category:",
        labelX = leftX,
        labelWidth = 64,
        centerY = -84,
        getValue = function() return cardsByTab[M.unitTexLayerTab[unit]] and M.unitTexLayerTab[unit] or "general" end,
        setValue = function(value)
            M.unitTexLayerTab[unit] = cardsByTab[value] and value or "general"
            ApplyTab()
        end,
    })
    if UP.RegisterControl then
        UP.RegisterControl(tabBar, ctx, "texture_layer.category_selector", "Category", "segment", "ephemeral")
    end
    ApplyTab()

    local function RefreshLayerControls()
        local on = ReadBool(unit, Key("Enabled"), false)
        for i = 1, #dependentControls do SetControlEnabled(dependentControls[i], on) end
        RefreshSourceControls()
        RefreshSizeControls()
        RefreshGradientControls()
    end
    RefreshLayerControls()
    M.TrackRefresh(ctx, RefreshLayerControls)
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "texture_layer",
        title = "Texture Layer",
        height = TEXLAYER_SECTION_H,
        placement = "after_load_conditions",
        order = 30,
        build = BuildTextureLayer,
    })
end
