-- Curated blacklist choices and labels for Unit and Group aura menus.
-- Prefer the current public aura catalogue on each cold-path request. Keep the
-- historical fallback available for standalone consumers and legacy profiles.
-- This owner builds menu choices; it never scans live aura containers.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Presets(Model, Common)
    local type = type
    local tostring = tostring
    local pairs = pairs
    local table_sort = table.sort
    local AuraFilter = Common.AuraFilter
    local NormalizeKind = Common.NormalizeKind
    local NormalizeScope = Common.NormalizeScope
    local SpellInfo = Common.SpellInfo

    local FALLBACK_PUBLIC_AURA_SPELLS = {
        PRESERVATION_EVOKER = {
            [355941] = true, [363502] = true, [364343] = true, [366155] = true,
            [367364] = true, [373267] = true, [376788] = true, [409895] = true,
        },
        AUGMENTATION_EVOKER = {
            [360827] = true, [395152] = true, [395296] = true, [410089] = true, [410263] = true,
            [410686] = true, [413984] = true,
        },
        RESTO_DRUID = {
            [774] = true, [8936] = true, [33763] = true, [48438] = true, [155777] = true,
            [439530] = true,
        },
        DISC_PRIEST = {
            [17] = true, [194384] = true, [1253593] = true,
            [1300008] = true, [1300009] = true,
        },
        HOLY_PRIEST = {
            [139] = true, [41635] = true, [77489] = true,
        },
        MISTWEAVER_MONK = {
            [115175] = true, [119611] = true, [124682] = true, [450769] = true,
            [1292922] = true,
        },
        RESTO_SHAMAN = {
            [974] = true, [383648] = true, [61295] = true, [382024] = true,
            [207400] = true, [444490] = true,
        },
        HOLY_PALADIN = {
            [53563] = true, [156322] = true, [156910] = true, [1244893] = true,
            [200025] = true, [431381] = true,
        },
        RAID_BUFFS = {
            [1459]   = true,   --- Arcane Intellect
            [6673]   = true,   --- Battle Shout
            [21562]  = true,   --- Power Word: Fortitude
            [369459] = true,   --- Source of Magic
            [462854] = true,   --- Skyfury
            [474754] = true,   --- Symbiotic Relationship
        },
        BLESSING_BRONZE = {
            [381732] = true, [381741] = true, [381746] = true, [381748] = true,
            [381749] = true, [381750] = true, [381751] = true, [381752] = true,
            [381753] = true, [381754] = true, [381756] = true, [381757] = true,
            [381758] = true,
        },
        SELF_BUFFS = {
            [433568] = true, [433583] = true,
        },
        ROGUE_POISONS = {
            [2823] = true, [8679] = true, [3408] = true, [5761] = true,
            [315584] = true, [381637] = true, [381664] = true,
        },
        SHAMAN_IMBUE = {
            [319773] = true, [319778] = true, [382021] = true, [382022] = true,
            [457496] = true, [457481] = true, [462757] = true, [462742] = true,
        },
        RESOURCE_AURAS = {
            [205473] = true, [260286] = true,
        },
        COOLDOWNS = {
            [8690] = true, [20608] = true,
        },
        SATED = {
            [57723] = true, [57724] = true, [80354] = true,
            [95809] = true, [160455] = true, [264689] = true,
            [390435] = true,
        },
        DESERTER = {
            [26013] = true, [71041] = true,
        },
        --- Never-secret debuff sets shared by EnhanceQoL's Global Aura Ignore list
        --- (copied with permission; EQoL re-verifies them daily against the Wago
        --- SpellMisc "Aura never secret" attribute).
        CHALLENGE_DEBUFFS = {
            [206151] = true, [308312] = true, [1254550] = true,
        },
        CLASS_UTILITY = {
            [124255] = true, [405189] = true, [462742] = true,
            [462757] = true, [1217607] = true,
        },
        SKYRIDING = {
            [369968] = true, [377234] = true, [388367] = true,
            [404464] = true, [404468] = true, [418590] = true,
            [427490] = true, [447959] = true, [447960] = true,
        },
    }

    local FALLBACK_PUBLIC_AURA_META = {
        { key = "RAID_BUFFS", label = "Long-term Raid Buffs", category = "Raid", tooltip = "Long duration raid buffs Blizzard exposes as non-secret." },
        { key = "PRESERVATION_EVOKER", label = "Preservation Evoker", category = "Healer", tooltip = "Dream Breath, Dream Flight, Echo, Reversion, Lifebind, Verdant Embrace." },
        { key = "AUGMENTATION_EVOKER", label = "Augmentation Evoker", category = "Support", tooltip = "Blistering Scales, Ebon Might, Prescience, Inferno's Blessing, Symbiotic Bloom, Shifting Sands." },
        { key = "RESTO_DRUID", label = "Restoration Druid", category = "Healer", tooltip = "Rejuvenation, Regrowth, Lifebloom, Wild Growth, Germination, Symbiotic Blooms." },
        { key = "DISC_PRIEST", label = "Discipline Priest", category = "Healer", tooltip = "Power Word: Shield, Atonement, Void Shield, and Unfolding Vision variants." },
        { key = "HOLY_PRIEST", label = "Holy Priest", category = "Healer", tooltip = "Renew, Prayer of Mending, Echo of Light." },
        { key = "MISTWEAVER_MONK", label = "Mistweaver Monk", category = "Healer", tooltip = "Soothing Mist, Renewing Mist, Enveloping Mist, Aspect of Harmony, Coalescence." },
        { key = "RESTO_SHAMAN", label = "Restoration Shaman", category = "Healer", tooltip = "Earth Shield, Riptide, Earthliving Weapon, Ancestral Vigor, Hydrobubble." },
        { key = "HOLY_PALADIN", label = "Holy Paladin", category = "Healer", tooltip = "Beacon variants, Eternal Flame, and Dawnlight." },
        { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", category = "Raid", tooltip = "All class-specific Blessing of the Bronze variants." },
        { key = "SELF_BUFFS", label = "Long-term Self Buffs", category = "Class", tooltip = "Rite of Sanctification and Rite of Adjuration." },
        { key = "ROGUE_POISONS", label = "Rogue Poisons", category = "Class", tooltip = "Deadly, Wound, Crippling, Numbing, Instant, Atrophic, Amplifying." },
        { key = "SHAMAN_IMBUE", label = "Shaman Imbuements", category = "Class", tooltip = "Windfury, Flametongue, Earthliving, Tidecaller's Guard, Thunderstrike Ward." },
        { key = "RESOURCE_AURAS", label = "Resource Auras", category = "Utility", tooltip = "Mage Icicles and Hunter Tip of the Spear." },
        { key = "COOLDOWNS", label = "Cooldowns", category = "Utility", tooltip = "Hearthstone and Shaman Reincarnation. Mythic+ teleports are not listed by Wowhead." },
        { key = "SATED", label = "Sated / Exhaustion", category = "Utility", tooltip = "Bloodlust/Heroism exhaustion lockout auras." },
        { key = "DESERTER", label = "Deserter", category = "Utility", tooltip = "Dungeon and battleground deserter lockout auras." },
        { key = "CHALLENGE_DEBUFFS", label = "Challenge/Instance Debuffs", category = "Utility", tooltip = "Challenger's Burden and other instance-wide timer debuffs." },
        { key = "CLASS_UTILITY", label = "Class/Utility Auras", category = "Utility", tooltip = "Stagger and similar class utility debuffs (Demon Hunter, Druid, Monk, Shaman)." },
        { key = "SKYRIDING", label = "Skyriding/Ride Along Auras", category = "Utility", tooltip = "Skyriding and Ride Along utility auras." },
    }

    local PRESET_CATEGORY_ORDER = { "Raid", "Healer", "Support", "Class", "Utility", "Other" }
    local PRESET_CATEGORY_RANK = { Raid = 1, Healer = 2, Support = 3, Class = 4, Utility = 5, Other = 6 }
    local PRESET_LABELS = {
        RAID_BUFFS = "Long-term Raid Buffs",
        PRESERVATION_EVOKER = "Preservation Evoker",
        AUGMENTATION_EVOKER = "Augmentation Evoker",
        RESTO_DRUID = "Restoration Druid",
        DISC_PRIEST = "Discipline Priest",
        HOLY_PRIEST = "Holy Priest",
        MISTWEAVER_MONK = "Mistweaver Monk",
        RESTO_SHAMAN = "Restoration Shaman",
        HOLY_PALADIN = "Holy Paladin",
        BLESSING_BRONZE = "Blessing of the Bronze",
        SELF_BUFFS = "Long-term Self Buffs",
        ROGUE_POISONS = "Rogue Poisons",
        SHAMAN_IMBUE = "Shaman Imbuements",
        RESOURCE_AURAS = "Resource Auras",
        COOLDOWNS = "Cooldowns",
        SATED = "Sated / Exhaustion",
        DESERTER = "Deserter",
        CHALLENGE_DEBUFFS = "Challenge/Instance Debuffs",
        CLASS_UTILITY = "Class/Utility Auras",
        SKYRIDING = "Skyriding/Ride Along Auras",
    }
    local PRESET_CATEGORIES = {
        RAID_BUFFS = "Raid",
        BLESSING_BRONZE = "Raid",
        PRESERVATION_EVOKER = "Healer",
        RESTO_DRUID = "Healer",
        DISC_PRIEST = "Healer",
        HOLY_PRIEST = "Healer",
        MISTWEAVER_MONK = "Healer",
        RESTO_SHAMAN = "Healer",
        HOLY_PALADIN = "Healer",
        AUGMENTATION_EVOKER = "Support",
        SELF_BUFFS = "Class",
        ROGUE_POISONS = "Class",
        SHAMAN_IMBUE = "Class",
        RESOURCE_AURAS = "Utility",
        COOLDOWNS = "Utility",
        SATED = "Utility",
        DESERTER = "Utility",
        CHALLENGE_DEBUFFS = "Utility",
        CLASS_UTILITY = "Utility",
        SKYRIDING = "Utility",
    }

    -- UnitFrame preset menus are lane-specific. These harmful-aura sets mirror
    -- EnhanceQoL's curated NeverSecret list, so every supported UnitFrame and
    -- Group Frame can expose the same exact Debuff presets honestly.
    local UNIT_BUFF_PRESET_KEYS = {
        RAID_BUFFS = true,
        PRESERVATION_EVOKER = true,
        AUGMENTATION_EVOKER = true,
        RESTO_DRUID = true,
        DISC_PRIEST = true,
        HOLY_PRIEST = true,
        MISTWEAVER_MONK = true,
        RESTO_SHAMAN = true,
        HOLY_PALADIN = true,
        BLESSING_BRONZE = true,
        SELF_BUFFS = true,
        ROGUE_POISONS = true,
        SHAMAN_IMBUE = true,
        RESOURCE_AURAS = true,
        COOLDOWNS = true,
    }
    local UNIT_CURATED_DEBUFF_PRESET_KEYS = {
        SATED = true,
        DESERTER = true,
        CHALLENGE_DEBUFFS = true,
    }

    local function PublicAuraPresetSpells()
        local af = AuraFilter()
        return (af and (af.PUBLIC_AURA_PRESET_SPELLS or af.DECLASSIFIED_SPELLS)) or FALLBACK_PUBLIC_AURA_SPELLS
    end

    local function PublicAuraPresetMeta()
        local af = AuraFilter()
        return (af and (af.PUBLIC_AURA_PRESET_META or af.DECLASSIFIED_META)) or FALLBACK_PUBLIC_AURA_META
    end

    local function CleanPresetLabel(key, fallback)
        if PRESET_LABELS[key] then return PRESET_LABELS[key] end
        fallback = tostring(fallback or key or "")
        fallback = fallback:gsub("^Midnight%s+", "")
        fallback = fallback:gsub("^Healer%s*%-%s*", "")
        return fallback ~= "" and fallback or tostring(key or "")
    end

    local function BuildBlacklistPresetValues(allowedKeys)
        local meta = PublicAuraPresetMeta()
        local buckets = {}
        local values = {}
        for i = 1, #meta do
            local item = meta[i]
            if item and item.key and (allowedKeys == nil or allowedKeys[item.key] == true) then
                local category = PRESET_CATEGORIES[item.key] or item.category or "Other"
                if not PRESET_CATEGORY_RANK[category] then category = "Other" end
                local bucket = buckets[category]
                if not bucket then
                    bucket = {}
                    buckets[category] = bucket
                end
                bucket[#bucket + 1] = {
                    value = item.key,
                    text = CleanPresetLabel(item.key, item.label),
                    tooltip = item.tooltip,
                    _order = i,
                }
            end
        end
        for i = 1, #PRESET_CATEGORY_ORDER do
            local category = PRESET_CATEGORY_ORDER[i]
            local bucket = buckets[category]
            if bucket and #bucket > 0 then
                table_sort(bucket, function(a, b) return (a._order or 0) < (b._order or 0) end)
                values[#values + 1] = { text = category, header = true, disabled = true, translate = false }
                for j = 1, #bucket do
                    local item = bucket[j]
                    item._order = nil
                    values[#values + 1] = item
                end
            end
        end
        return values
    end

    local function BlacklistPresetKeysForKind(kind)
        if NormalizeKind(kind) == "debuff" then return UNIT_CURATED_DEBUFF_PRESET_KEYS end
        return UNIT_BUFF_PRESET_KEYS
    end

    function Model.BlacklistPresetValues()
        return BuildBlacklistPresetValues(nil)
    end

    function Model.UnitBlacklistPresetAllowed(scope, kind, presetKey)
        kind = NormalizeKind(kind)
        presetKey = tostring(presetKey or "")
        if NormalizeScope(scope) == "shared" then return false end
        return BlacklistPresetKeysForKind(kind)[presetKey] == true
    end

    function Model.UnitBlacklistPresetValues(scope, kind)
        kind = NormalizeKind(kind)
        if NormalizeScope(scope) == "shared" then return {} end
        return BuildBlacklistPresetValues(BlacklistPresetKeysForKind(kind))
    end

    function Model.UnitBlacklistDefaultPreset(scope, kind)
        kind = NormalizeKind(kind)
        if NormalizeScope(scope) == "shared" then return nil end
        if kind == "buff" then return "RAID_BUFFS" end
        return "SATED"
    end

    function Model.BlacklistSpellValues(presetKey)
        local spells = PublicAuraPresetSpells()
        local set = spells and spells[presetKey or "RAID_BUFFS"] or nil
        local values = {}
        if type(set) ~= "table" then return values end
        for spellID in pairs(set) do
            local id, name, icon = SpellInfo(spellID)
            if id then
                values[#values + 1] = {
                    value = tostring(id),
                    text = (type(name) == "string" and name ~= "" and name or "Spell") .. " (#" .. tostring(id) .. ")",
                    icon = icon,
                }
            end
        end
        table_sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
        return values
    end

    function Model.UnitBlacklistSpellValues(scope, kind, presetKey)
        if not Model.UnitBlacklistPresetAllowed(scope, kind, presetKey) then return {} end
        return Model.BlacklistSpellValues(presetKey)
    end

    function Model.AddBlacklistPresetSpell(scope, spellID, kind)
        return Model.AddBlacklistSpell(scope, spellID, kind)
    end

    function Model.AddBlacklistPresetGroup(scope, presetKey, kind)
        local values = Model.UnitBlacklistSpellValues(scope, kind, presetKey)
        local count = 0
        for i = 1, #values do
            local item = values[i]
            if item and item.value and Model.AddBlacklistSpell(scope, item.value, kind) then
                count = count + 1
            end
        end
        return count
    end


    -- Private dependency API; public menu methods remain on A3.MenuModel.
    return {
        BlacklistPresetKeysForKind = BlacklistPresetKeysForKind,
        BuildBlacklistPresetValues = BuildBlacklistPresetValues,
        FALLBACK_PUBLIC_AURA_META = FALLBACK_PUBLIC_AURA_META,
        FALLBACK_PUBLIC_AURA_SPELLS = FALLBACK_PUBLIC_AURA_SPELLS,
        PublicAuraPresetMeta = PublicAuraPresetMeta,
        PublicAuraPresetSpells = PublicAuraPresetSpells,
    }
end
