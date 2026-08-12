--- Auras3/MSUF_Auras3_DefensiveData.lua
--- Curated defensive BUFF aura IDs for the normal Big Defensive filter and
--- the broader player-only defensive lane.
---
--- Data baseline:
---   Retail 12.0.7.68453 (2026-07-18 hotfix data)
---   PTR    12.1.0.68745 (2026-07-16 hotfix data)
--- Aura IDs were cross-checked against the local SimulationCraft SpellDataDump
--- and the local WeakAuras player-buff trigger templates. This intentionally
--- stores aura IDs (not always the matching action/spellbook ID), including
--- passive defensive procs and defensive maintenance buffs.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

A3.PlayerDefensiveDataVersion = "12.0.7.68453+12.1.0.68745"

--- Spellbook/talent IDs that differ from the spell ID carried by the visible
--- buff. Blizzard's native includeSpellIDs filter compares only against
--- auraData.spellId, so compile these aliases once when building a lane.
A3.AuraSpellIDAliases = {
    [185313] = { 185422 }, -- Shadow Dance action -> Shadow Dance buff
    [382514] = { 386237 }, -- Fade to Nothing talent -> Fade to Nothing buff
}

function A3.AddAuraSpellIDAndAliases(out, spellID)
    spellID = tonumber(spellID)
    if not (out and spellID and spellID > 0) then return end
    spellID = math.floor(spellID + 0.5)
    out[spellID] = true
    local aliases = A3.AuraSpellIDAliases[spellID]
    for i = 1, type(aliases) == "table" and #aliases or 0 do
        local auraSpellID = tonumber(aliases[i])
        if auraSpellID and auraSpellID > 0 then out[math.floor(auraSpellID + 0.5)] = true end
    end
end

--- Curated major-defensive aura IDs used by the normal Unit/Group "Big
--- Defensive" filter. This is deliberately narrower than PlayerDefensiveData:
--- it mirrors the enabled EllesmereUI 8.8.3 Defensives preset and excludes its
--- disabled/passive/maintenance entries. Blizzard's BIG_DEFENSIVE token remains
--- the fallback where helpful Spell-ID candidate filters are identity-restricted.
A3.BigDefensiveDataVersion = "EUI-8.8.3+12.1.0.69189"
A3.BigDefensiveData = {
    DEATHKNIGHT = {
        { 48707, "Anti-Magic Shell", { 444741 } },
        { 48792, "Icebound Fortitude" },
        { 55233, "Vampiric Blood" },
        { 101568, "Dark Succor" },
    },
    DEMONHUNTER = {
        { 212800, "Blur" },
        { 187827, "Metamorphosis" },
        { 207771, "Fiery Brand" },
    },
    DRUID = {
        { 22812, "Barkskin" },
        { 22842, "Frenzied Regeneration" },
        { 61336, "Survival Instincts" },
        { 1261872, "Survival Instincts" },
    },
    EVOKER = {
        { 404381, "Defensive" },
        { 363916, "Obsidian Scales" },
        { 374349, "Renewing Blaze" },
    },
    HUNTER = {
        { 186265, "Aspect of the Turtle" },
        { 264735, "Survival of the Fittest" },
    },
    MAGE = {
        { 342246, "Alter Time" },
        { 45438, "Ice Block" },
        { 414658, "Ice Cold" },
        { 449336, "Merely a Setback" },
        { 1309793, "Defensive" },
    },
    MONK = {
        { 122783, "Diffuse Magic" },
        { 115203, "Fortifying Brew", { 120954 } },
        { 125174, "Touch of Karma" },
        { 132578, "Invoke Niuzao" },
        { 322507, "Celestial Brew" },
        { 1241059, "Defensive" },
    },
    PALADIN = {
        { 498, "Divine Protection", { 403876 } },
        { 642, "Divine Shield" },
        { 31850, "Ardent Defender" },
        { 86659, "Guardian of Ancient Kings" },
    },
    PRIEST = {
        { 19236, "Desperate Prayer" },
        { 47585, "Dispersion" },
        { 586, "Fade" },
        { 193065, "Protective Light" },
        { 27827, "Spirit of Redemption" },
    },
    ROGUE = {
        { 31224, "Cloak of Shadows" },
        { 5277, "Evasion" },
        { 1966, "Feint" },
        { 185311, "Crimson Vial" },
    },
    SHAMAN = {
        { 108271, "Astral Shift" },
        { 260881, "Spirit Wolf" },
    },
    WARLOCK = {
        { 108416, "Dark Pact" },
        { 104773, "Unending Resolve" },
        { 132413, "Shadow Bulwark" },
        { 387636, "Soulburn: Healthstone" },
        { 389614, "Abyss Walker" },
    },
    WARRIOR = {
        { 118038, "Die by the Sword" },
        { 184364, "Enraged Regeneration" },
        { 190456, "Ignore Pain", { 1277297 } },
        { 147833, "Intervene" },
        { 385391, "Spell Block" },
        { 871, "Shield Wall" },
    },
}

local bigDefensiveSpellIDHash
local bigDefensiveSpellIDSignature

--- Build the immutable all-class hash lazily. The normal Big Defensive filter
--- is used on mixed Party/Raid units, so class-local filtering would omit valid
--- auras whenever the unit token changes owner.
function A3.GetBigDefensiveSpellIDHash()
    if bigDefensiveSpellIDHash then
        return bigDefensiveSpellIDHash, bigDefensiveSpellIDSignature
    end
    local hash, ids = {}, {}
    for _, entries in pairs(A3.BigDefensiveData) do
        for i = 1, #entries do
            local entry = entries[i]
            local spellID = tonumber(entry[1])
            if spellID and spellID > 0 then
                spellID = math.floor(spellID + 0.5)
                if hash[spellID] ~= true then ids[#ids + 1] = spellID end
                hash[spellID] = true
            end
            local alts = entry[3]
            for j = 1, type(alts) == "table" and #alts or 0 do
                local altID = tonumber(alts[j])
                if altID and altID > 0 then
                    altID = math.floor(altID + 0.5)
                    if hash[altID] ~= true then ids[#ids + 1] = altID end
                    hash[altID] = true
                end
            end
        end
    end
    table.sort(ids)
    local parts = {}
    for i = 1, #ids do parts[i] = tostring(ids[i]) end
    bigDefensiveSpellIDHash = hash
    bigDefensiveSpellIDSignature = "bigDefensive:" .. table.concat(parts, ",")
    return bigDefensiveSpellIDHash, bigDefensiveSpellIDSignature
end

A3.PlayerDefensiveData = {
    DEATHKNIGHT = {
        { 48707, "Anti-Magic Shell" }, { 48792, "Icebound Fortitude" },
        { 49039, "Lichborne" }, { 55233, "Vampiric Blood" },
        { 77535, "Blood Shield" }, { 81256, "Dancing Rune Weapon" },
        { 116888, "Shroud of Purgatory" }, { 145629, "Anti-Magic Zone" },
        { 194679, "Rune Tap" }, { 195181, "Bone Shield" },
        { 207203, "Frost Shield" }, { 219809, "Tombstone" },
        { 374748, "Perseverance of the Ebon Blade" },
        { 391459, "Sanguine Ground" }, { 391519, "Umbilicus Eternus" },
        { 434034, "Blood-Soaked Ground" }, { 434105, "Vampiric Aura" },
        { 440289, "Rune Carved Plates" }, { 443532, "Bind in Darkness" },
    },
    DEMONHUNTER = {
        { 162264, "Metamorphosis" }, { 187827, "Metamorphosis" },
        { 196555, "Netherwalk" }, { 203819, "Demon Spikes" },
        { 209426, "Darkness" }, { 212800, "Blur" },
        { 212988, "Painbringer" }, { 263648, "Soul Barrier" },
        { 272987, "Revel in Pain" }, { 326863, "Ruinous Bulwark" },
        { 391171, "Calcified Spikes" }, { 391234, "Soulmonger" },
        { 393009, "Fel Flame Fortification" },
        { 427901, "Deflecting Dance" }, { 442715, "Blade Ward" },
        { 442788, "Incorruptible Spirit" },
    },
    DRUID = {
        { 22812, "Barkskin" }, { 22842, "Frenzied Regeneration" },
        { 61336, "Survival Instincts" }, { 192081, "Ironfur" },
        { 135286, "Tooth and Claw" }, { 200851, "Rage of the Sleeper" },
        { 203975, "Earthwarden" }, { 213680, "Guardian of Elune" },
        { 372505, "Ursoc's Fury" }, { 385787, "Matted Fur" },
        { 393903, "Ursine Vigor" }, { 400126, "Forestwalk" },
        { 433749, "Protective Growth" },
    },
    EVOKER = {
        { 357170, "Time Dilation" }, { 360827, "Blistering Scales" },
        { 363916, "Obsidian Scales" }, { 373862, "Temporal Anomaly" },
        { 374227, "Zephyr" }, { 374348, "Renewing Blaze" },
        { 403264, "Black Attunement" }, { 403295, "Black Attunement" },
        { 407254, "Black Aspect's Favor" }, { 410355, "Stretch Time" },
        { 410651, "Molten Blood" }, { 431872, "Temporality" },
    },
    HUNTER = {
        { 5384, "Feign Death" }, { 53480, "Roar of Sacrifice" },
        { 186265, "Aspect of the Turtle" }, { 199483, "Camouflage" },
        { 202748, "Survival Tactics" }, { 264735, "Survival of the Fittest" },
        { 385540, "Rejuvenating Wind" }, { 392956, "Fortitude of the Bear" },
        { 451447, "Don't Look Back" }, { 472708, "Shell Cover" },
    },
    MAGE = {
        { 11426, "Ice Barrier" }, { 45438, "Ice Block" },
        { 55342, "Mirror Image" }, { 87023, "Cauterize" },
        { 110960, "Greater Invisibility" },
        { 235313, "Blazing Barrier" }, { 235450, "Prismatic Barrier" },
        { 342246, "Alter Time" }, { 382290, "Tempest Barrier" },
        { 414658, "Ice Cold" }, { 449331, "Merely a Setback" },
        { 449336, "Merely a Setback" },
    },
    MONK = {
        { 115176, "Zen Meditation" }, { 120954, "Fortifying Brew" },
        { 122783, "Diffuse Magic" }, { 125174, "Touch of Karma" },
        { 116849, "Life Cocoon" },
        { 195630, "Elusive Brawler" }, { 215479, "Shuffle" },
        { 322507, "Celestial Brew" }, { 393515, "Pretense of Instability" },
        { 406139, "Chi Cocoon" }, { 414143, "Yu'lon's Grace" },
        { 432180, "Dance of the Wind" }, { 442749, "Niuzao's Protection" },
        { 448508, "Jade Sanctuary" }, { 451299, "Chi Cocoon" },
        { 454494, "August Blessing" }, { 455071, "Ox Stance" },
    },
    PALADIN = {
        { 465, "Devotion Aura" }, { 498, "Divine Protection" },
        { 642, "Divine Shield" },
        { 1022, "Blessing of Protection" }, { 31850, "Ardent Defender" },
        { 31821, "Aura Mastery" }, { 148039, "Barrier of Faith" },
        { 184662, "Shield of Vengeance" },
        { 86659, "Guardian of Ancient Kings" }, { 132403, "Shield of the Righteous" },
        { 204018, "Blessing of Spellwarding" }, { 209388, "Bulwark of Order" },
        { 211210, "Protection of Tyr" }, { 280375, "Redoubt" },
        { 379017, "Faith's Armor" }, { 379041, "Faith in the Light" },
        { 385724, "Barricade of Faith" }, { 386556, "Inner Light" },
        { 387792, "Empyreal Ward" }, { 387804, "Echoing Protection" },
        { 389539, "Sentinel" }, { 393038, "Strength in Adversity" },
        { 403876, "Divine Protection" }, { 432496, "Holy Bulwark" },
        { 461578, "Saved by the Light" }, { 461867, "Sacrosanct Crusade" },
    },
    PRIEST = {
        { 17, "Power Word: Shield" }, { 586, "Fade" },
        { 19236, "Desperate Prayer" }, { 33206, "Pain Suppression" },
        { 47585, "Dispersion" }, { 47753, "Divine Aegis" },
        { 47788, "Guardian Spirit" }, { 81782, "Power Word: Barrier" },
        { 114214, "Angelic Bulwark" }, { 193065, "Protective Light" },
        { 271466, "Luminous Barrier" }, { 377066, "Mental Fortitude" },
        { 390677, "Inspiration" }, { 428934, "Premonition of Solace" },
    },
    ROGUE = {
        { 1966, "Feint" }, { 5277, "Evasion" },
        { 31224, "Cloak of Shadows" }, { 45182, "Cheating Death" },
        { 185311, "Crimson Vial" }, { 386165, "Cloaked in Shadows" },
        { 386237, "Fade to Nothing" }, { 393971, "Soothing Darkness" },
    },
    SHAMAN = {
        { 974, "Earth Shield" }, { 108271, "Astral Shift" },
        { 114893, "Stone Bulwark" }, { 201633, "Earthen Wall" },
        { 207400, "Ancestral Vigor" }, { 260881, "Spirit Wolf" },
        { 378078, "Spiritwalker's Aegis" }, { 381755, "Earth Elemental" },
        { 381761, "Primordial Bond" }, { 383648, "Earth Shield" },
        { 457387, "Wind Barrier" }, { 462568, "Elemental Resistance" },
    },
    WARLOCK = {
        { 104773, "Unending Resolve" }, { 108366, "Soul Leech" },
        { 108416, "Dark Pact" }, { 386647, "Lifeblood" },
        { 387636, "Soulburn: Healthstone" }, { 389614, "Abyss Walker" },
        { 434559, "Infernal Vitality" }, { 434561, "Infernal Bulwark" },
    },
    WARRIOR = {
        { 871, "Shield Wall" }, { 12975, "Last Stand" },
        { 23920, "Spell Reflection" }, { 97463, "Rallying Cry" },
        { 118038, "Die by the Sword" }, { 132404, "Shield Block" },
        { 184364, "Enraged Regeneration" }, { 190456, "Ignore Pain" },
        { 351077, "Second Wind" }, { 386029, "Brace For Impact" },
        { 386208, "Defensive Stance" }, { 392966, "Spell Block" },
        { 437152, "Steadfast as the Peaks" },
        { 438591, "Keep Your Feet on the Ground" },
    },
}
