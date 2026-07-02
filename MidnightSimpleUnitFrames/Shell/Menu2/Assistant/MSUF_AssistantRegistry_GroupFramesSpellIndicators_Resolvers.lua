-- Assistant GroupFrames spell/corner indicator resolver helpers.
-- Loaded before the spell indicator core; consumed by the core helper factory.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildSpellIndicatorResolvers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local Namespace = ctx.MSUF or MSUF
    local SPEC_VALUES = ctx.SPEC_VALUES or {}
    local SPEC_DISPLAY_LABELS = ctx.SPEC_DISPLAY_LABELS or {}
    local SPEC_ALIASES = ctx.SPEC_ALIASES or {}

    local function LookupKey(value)
        return tostring(value or ""):lower():gsub("[^%w]+", "")
    end

    local function SpellRuntime()
        local gf = Namespace and Namespace.GF
        return (gf and gf.SpellIndicators) or _G.MSUF_GF_SpellIndicators
    end

    local FALLBACK_TRACKABLE_AURAS = {
        PreservationEvoker = { "Echo", "Reversion", "EchoReversion", "DreamBreath", "EchoDreamBreath", "DreamFlight", "Lifebind", "TimeDilation", "Rewind", "VerdantEmbrace" },
        AugmentationEvoker = { "Prescience", "ShiftingSands", "BlisteringScales", "InfernosBlessing", "SymbioticBloom", "EbonMight", "SourceOfMagic", "SensePower" },
        RestorationDruid = { "Rejuvenation", "Regrowth", "Lifebloom", "Germination", "WildGrowth", "SymbioticRelationship", "SymbioticBlooms", "IronBark" },
        DisciplinePriest = { "Atonement", "PowerWordShield", "PrayerOfMending", "VoidShield", "PainSuppression", "PowerInfusion" },
        HolyPriest = { "Renew", "EchoOfLight", "PrayerOfMending", "GuardianSpirit", "PowerInfusion" },
        ShadowPriest = { "PowerInfusion" },
        MistweaverMonk = { "RenewingMist", "EnvelopingMist", "SoothingMist", "AspectOfHarmony", "Coalescence", "LifeCocoon", "StrengthOfTheBlackOx" },
        RestorationShaman = { "Riptide", "EarthShield", "AncestralVigor", "EarthlivingWeapon", "Hydrobubble" },
        HolyPaladin = { "BeaconOfLight", "BeaconOfFaith", "BeaconOfVirtue", "BeaconOfTheSavior", "EternalFlame", "Dawnlight", "BlessingOfProtection", "HolyArmaments", "BlessingOfSacrifice", "BlessingOfFreedom" },
        ProtectionPaladin = { "BlessingOfProtection", "BlessingOfSacrifice", "BlessingOfFreedom" },
        RetributionPaladin = { "BlessingOfProtection", "BlessingOfSacrifice", "BlessingOfFreedom" },
    }

    local FALLBACK_AURA_LABELS = {
        EchoReversion = "Echo Reversion",
        DreamBreath = "Dream Breath",
        EchoDreamBreath = "Echo Dream Breath",
        DreamFlight = "Dream Flight",
        TimeDilation = "Time Dilation",
        VerdantEmbrace = "Verdant Embrace",
        ShiftingSands = "Shifting Sands",
        BlisteringScales = "Blistering Scales",
        InfernosBlessing = "Infernos Blessing",
        SymbioticRelationship = "Symbiotic Relationship",
        SymbioticBlooms = "Symbiotic Blooms",
        IronBark = "Ironbark",
        PowerWordShield = "Power Word Shield",
        PrayerOfMending = "Prayer of Mending",
        VoidShield = "Void Shield",
        PainSuppression = "Pain Suppression",
        PowerInfusion = "Power Infusion",
        EchoOfLight = "Echo of Light",
        GuardianSpirit = "Guardian Spirit",
        RenewingMist = "Renewing Mist",
        EnvelopingMist = "Enveloping Mist",
        SoothingMist = "Soothing Mist",
        AspectOfHarmony = "Aspect of Harmony",
        LifeCocoon = "Life Cocoon",
        StrengthOfTheBlackOx = "Strength of the Black Ox",
        EarthShield = "Earth Shield",
        AncestralVigor = "Ancestral Vigor",
        EarthlivingWeapon = "Earthliving Weapon",
        BeaconOfLight = "Beacon of Light",
        BeaconOfFaith = "Beacon of Faith",
        BeaconOfVirtue = "Beacon of Virtue",
        BeaconOfTheSavior = "Beacon of the Savior",
        EternalFlame = "Eternal Flame",
        BlessingOfProtection = "Blessing of Protection",
        HolyArmaments = "Holy Armaments",
        BlessingOfSacrifice = "Blessing of Sacrifice",
        BlessingOfFreedom = "Blessing of Freedom",
    }

    local function FallbackTrackableList(specKey)
        local names = FALLBACK_TRACKABLE_AURAS[specKey]
        if type(names) ~= "table" then return nil end
        local out = {}
        for i = 1, #names do
            local name = names[i]
            out[#out + 1] = { name = name, display = FALLBACK_AURA_LABELS[name] or tostring(name):gsub("(%l)(%u)", "%1 %2") }
        end
        return out
    end

    local function TrackableAuras()
        local runtime = SpellRuntime()
        if runtime and type(runtime.TrackableAuras) == "table" then return runtime.TrackableAuras end
        return FALLBACK_TRACKABLE_AURAS
    end

    local function CamelCaseDisplay(value)
        value = tostring(value or "")
        if value == "" then return "" end
        return (value:gsub("(%l)(%u)", "%1 %2"))
    end

    local function SpecDisplay(specKey)
        if SPEC_DISPLAY_LABELS[specKey] then return SPEC_DISPLAY_LABELS[specKey] end
        local info = SpellRuntime() and SpellRuntime().SpecInfo and SpellRuntime().SpecInfo[specKey]
        return (info and info.display) or CamelCaseDisplay(specKey)
    end

    local function ResolveSpec(value)
        local compact = LookupKey(value)
        if compact == "" then return nil end
        local bestSpecKey, bestScore
        for alias, specKey in pairs(SPEC_ALIASES) do
            local aliasKey = LookupKey(alias)
            local score
            if compact == aliasKey then
                score = 10000 + #aliasKey
            elseif #aliasKey >= 5 and compact:find(aliasKey, 1, true) then
                score = #aliasKey
            end
            if score and (not bestScore or score > bestScore) then
                bestSpecKey, bestScore = specKey, score
            end
        end
        if bestSpecKey then return bestSpecKey end
        for i = 1, #SPEC_VALUES do
            local specKey = SPEC_VALUES[i]
            if compact == LookupKey(specKey) or compact == LookupKey(SpecDisplay(specKey)) then return specKey end
        end
        local specs = SpellRuntime() and SpellRuntime().SpecInfo
        if type(specs) == "table" then
            for specKey, info in pairs(specs) do
                local displayKey = LookupKey(info and info.display)
                if compact == LookupKey(specKey) or compact == displayKey or (#displayKey >= 5 and compact:find(displayKey, 1, true)) then return specKey end
            end
        end
        return nil
    end

    local function FindAuraInSpec(specKey, text)
        text = tostring(text or "")
        local compact = LookupKey(text)
        local runtime = SpellRuntime()
        local list = runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
        if type(list) ~= "table" then list = FallbackTrackableList(specKey) end
        local bestName, bestDisplay, bestScore
        if type(list) == "table" then
            for i = 1, #list do
                local info = list[i]
                local name = info and info.name
                if name then
                    local display = info.display or name
                    local nameKey = LookupKey(name)
                    local displayKey = LookupKey(display)
                    local score
                    if compact == nameKey or compact == displayKey then score = math.max(#nameKey, #displayKey)
                    elseif #nameKey >= 4 and compact:find(nameKey, 1, true) then score = #nameKey
                    elseif #displayKey >= 4 and compact:find(displayKey, 1, true) then score = #displayKey end
                    if score and (not bestScore or score > bestScore) then bestName, bestDisplay, bestScore = name, display, score end
                end
            end
        end
        local ids = runtime and runtime.SpellIDs and runtime.SpellIDs[specKey]
        local numberText = text:match("%d+")
        if type(ids) == "table" and numberText then
            for auraName, spellID in pairs(ids) do
                if tostring(spellID) == numberText then return auraName, auraName end
            end
        end
        return bestName, bestDisplay
    end

    local function ResolveAura(specKey, text)
        specKey = ResolveSpec(specKey) or specKey
        if specKey then
            local aura, display = FindAuraInSpec(specKey, text)
            return aura, specKey, display
        end
        local trackable = TrackableAuras()
        local bestAura, bestSpec, bestDisplay, bestScore
        if type(trackable) == "table" then
            for key in pairs(trackable) do
                local aura, display = FindAuraInSpec(key, text)
                if aura then
                    local score = #LookupKey(display or aura)
                    if not bestScore or score > bestScore then
                        bestAura, bestSpec, bestDisplay, bestScore = aura, key, display, score
                    elseif score == bestScore and aura ~= bestAura then
                        bestAura, bestSpec, bestDisplay = nil, nil, nil
                    end
                end
            end
        end
        return bestAura, bestSpec, bestDisplay
    end

    Assistant.ResolveGroupSpellSpec = ResolveSpec
    Assistant.ResolveGroupSpellAura = ResolveAura
    Assistant.GroupSpellSpecDisplay = SpecDisplay

    return {
        ResolveAura = ResolveAura,
        ResolveSpec = ResolveSpec,
        SpecDisplay = SpecDisplay,
        SpellRuntime = SpellRuntime,
    }
end
