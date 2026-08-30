--- Auras3/MSUF_Auras3_GroupHighlightsData.lua
--- MSUF-owned Retail aura IDs for the combined Group Highlights buff filter.
---
--- Data baseline:
---   Retail 12.1.0.69497
---   MiniAuras 5.27.0 Party/Raid helpful-aura catalog (coverage reference)
---
--- MiniAuras was used only as a coverage reference. Its full active default
--- includes recurring rotational, persistent, proc, and minor utility states.
--- MSUF deliberately removes those noisy states and keeps 67 defensive/healer
--- cooldown auras, 53 major offensive/support cooldown auras, and the two
--- exact Shroud membership auras. MSUF has no runtime dependency on MiniAuras
--- and owns this versioned catalog.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local DATA_VERSION = "12.1.0.69497-v1"
local EXPECTED_COUNT = 122
local DATA_SIGNATURE = "groupHighlights:" .. DATA_VERSION .. ":" .. EXPECTED_COUNT
local NEVER_MATCHED_SPELL_ID = 0

A3.GroupHighlightsDataVersion = DATA_VERSION
A3.GroupHighlightsDataCount = EXPECTED_COUNT

--- Aura spell IDs, not necessarily the matching spellbook/action IDs. The
--- categories below document why an aura is present; the runtime filter uses
--- their single combined set.
local groupHighlightSpellIDs = {
    -- Defensive and healer-throughput cooldowns (67).
    642, -- Divine Shield
    740, -- Tranquility
    871, -- Shield Wall
    1022, -- Blessing of Protection
    1966, -- Feint
    5277, -- Evasion
    6940, -- Blessing of Sacrifice
    19236, -- Desperate Prayer
    22812, -- Barkskin
    31224, -- Cloak of Shadows
    31821, -- Aura Mastery
    31850, -- Ardent Defender
    33206, -- Pain Suppression
    45438, -- Ice Block
    47585, -- Dispersion
    47788, -- Guardian Spirit
    48707, -- Anti-Magic Shell
    48792, -- Icebound Fortitude
    49039, -- Lichborne
    53480, -- Roar of Sacrifice
    55233, -- Vampiric Blood
    61336, -- Survival Instincts
    64843, -- Divine Hymn
    81256, -- Dancing Rune Weapon
    81782, -- Power Word: Barrier (allied zone aura)
    97463, -- Rallying Cry
    102342, -- Ironbark
    104773, -- Unending Resolve
    108271, -- Astral Shift
    108416, -- Dark Pact
    110960, -- Greater Invisibility
    116849, -- Life Cocoon
    118038, -- Die by the Sword
    120954, -- Fortifying Brew
    125174, -- Touch of Karma
    145629, -- Anti-Magic Zone
    147833, -- Intervene
    184364, -- Enraged Regeneration
    186265, -- Aspect of the Turtle
    196718, -- Darkness
    199448, -- Blessing of Sacrifice
    200183, -- Apotheosis
    203819, -- Demon Spikes
    204018, -- Blessing of Spellwarding
    207771, -- Fiery Brand
    209426, -- Darkness
    212295, -- Nether Ward
    212800, -- Blur
    228050, -- Guardian of the Forgotten Queen
    264735, -- Survival of the Fittest
    325174, -- Spirit Link
    342246, -- Alter Time
    354540, -- Nimble Brew
    354610, -- Glimpse
    357170, -- Time Dilation
    363534, -- Rewind
    363916, -- Obsidian Scales
    370960, -- Emerald Communion
    374227, -- Zephyr
    384100, -- Berserker Shout
    389539, -- Sentinel
    409293, -- Burrow
    414658, -- Ice Cold
    414664, -- Mass Invisibility
    421453, -- Ultimate Penitence
    473909, -- Ancient of Lore
    1309793, -- Refractive Images

    -- Major offensive and decision-relevant support cooldowns (53).
    498, -- Divine Protection
    1044, -- Blessing of Freedom
    1719, -- Recklessness
    8178, -- Grounding Totem
    10060, -- Power Infusion
    12472, -- Icy Veins
    13750, -- Adrenaline Rush
    19574, -- Bestial Wrath
    23920, -- Spell Reflection
    29166, -- Innervate
    31884, -- Avenging Wrath
    42650, -- Army of the Dead
    50334, -- Berserk
    51271, -- Pillar of Frost
    102543, -- Incarnation: Avatar of Ashamane
    102558, -- Incarnation: Guardian of Ursoc
    106951, -- Berserk
    107574, -- Avatar
    114051, -- Ascendance
    114052, -- Ascendance
    117679, -- Incarnation: Tree of Life
    121471, -- Shadow Blades
    132578, -- Invoke Niuzao, the Black Ox
    162264, -- Metamorphosis
    185422, -- Shadow Dance
    187827, -- Metamorphosis
    190319, -- Combustion
    191634, -- Stormkeeper
    194249, -- Voidform
    198144, -- Ice Form
    210256, -- Blessing of Sanctuary
    216331, -- Avenging Crusader
    288613, -- Trueshot
    353319, -- Peaceweaver
    357210, -- Deep Breath
    360194, -- Deathmark
    365362, -- Arcane Surge
    375087, -- Dragonrage
    378441, -- Time Stop
    378464, -- Nullifying Shroud
    383410, -- Celestial Alignment
    390260, -- Commander of the Dead
    390414, -- Incarnation: Chosen of Elune
    403876, -- Divine Protection
    410358, -- Anti-Magic Shell (Spellwarding)
    442726, -- Malevolence
    454351, -- Avenging Wrath
    466772, -- Doom Winds
    1217607, -- Void Metamorphosis
    1219480, -- Ascendance
    1249625, -- Zenith
    1250646, -- Takedown
    1276767, -- Tyrant's Oblation

    -- Tactical group-membership state (2). Shroud uses distinct auras for
    -- its Rogue/caster and allied recipients, so both exact IDs are required.
    114018, -- Shroud of Concealment (Rogue/caster aura)
    115834, -- Shroud of Concealment (allied recipient aura)
}

local sharedSpellIDHash
local sharedSpellIDSignature
local sharedSpellIDCount

local function BuildFailClosedResult()
    -- Keep the error result nonempty so MSUF's generic normalizers cannot
    -- reduce an empty ID map to nil and accidentally remove the restriction.
    sharedSpellIDHash = { [NEVER_MATCHED_SPELL_ID] = true }
    sharedSpellIDSignature = "groupHighlights:" .. DATA_VERSION .. ":invalid"
    sharedSpellIDCount = 0
    groupHighlightSpellIDs = nil
end

--- Return the lazily-built all-class set. The returned hash is shared by every
--- Party/Raid configuration and must be treated as immutable by callers.
---@return table<number, boolean> spellIDHash
---@return string signature
---@return number count
function A3.GetGroupHighlightsSpellIDHash()
    if sharedSpellIDHash then
        return sharedSpellIDHash, sharedSpellIDSignature, sharedSpellIDCount
    end

    if type(groupHighlightSpellIDs) ~= "table" then
        BuildFailClosedResult()
        return sharedSpellIDHash, sharedSpellIDSignature, sharedSpellIDCount
    end

    local hash, count = {}, 0
    local valid = true

    for i = 1, #groupHighlightSpellIDs do
        local spellID = groupHighlightSpellIDs[i]
        if type(spellID) ~= "number"
            or spellID <= 0
            or spellID ~= math.floor(spellID)
            or hash[spellID] == true
        then
            valid = false
            break
        end
        hash[spellID] = true
        count = count + 1
    end

    if not valid or count ~= EXPECTED_COUNT then
        BuildFailClosedResult()
        return sharedSpellIDHash, sharedSpellIDSignature, sharedSpellIDCount
    end

    sharedSpellIDHash = hash
    sharedSpellIDSignature = DATA_SIGNATURE
    sharedSpellIDCount = count
    groupHighlightSpellIDs = nil

    return sharedSpellIDHash, sharedSpellIDSignature, sharedSpellIDCount
end
