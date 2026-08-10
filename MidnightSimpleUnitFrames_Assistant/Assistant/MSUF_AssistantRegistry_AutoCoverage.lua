-- Assistant auto-coverage fallback registration.
--
-- Closes the raw-coverage gap mechanically: every safe scalar DB path that no
-- hand-written registry entry reaches gets a generated English setting with a
-- label and aliases derived from the key name, DB accessors, and the broadest
-- safe apply for its scope. Only booleans have a proven generated write domain;
-- numbers and strings stay read-only until a curated entry supplies bounds or
-- allowed values. Hand-written entries always win
-- (RegisterSetting dedupes by key; the covered-set check also honors
-- unit+attribute), so this layer only ever fills holes.
--
-- Generated entries are marked `generated = true` so the coverage audit,
-- knowledge dump, and future curation passes can tell them apart. They are the
-- floor, not the ceiling: /msufcoverage stubs <scope> still produces proper
-- stubs when a key deserves curated aliases and a precise apply.
--
-- Filled lazily on the first assistant parse (DB seeded, all domains
-- registered) and again on demand via /msufcoverage fill (e.g. after a profile
-- import materializes new keys). Re-running is idempotent.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Auto = A.AutoCoverage or {}
A.AutoCoverage = Auto

local UNIT_SCOPES = {
    player = true, target = true, targettarget = true, focustarget = true,
    focus = true, pet = true, boss = true,
}
local GROUP_SCOPES = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
}
local FLAT_SCOPES = { general = true, bars = true, gameplay = true }

-- Exact raw-storage projections which are already owned by a reviewed public
-- setting.  AutoCoverage must not publish a second controller for these keys:
-- doing so makes a natural request compete with the real control and can even
-- bypass its value semantics (for example, treating one RGB channel as an
-- independent unbounded number).  CoverageAudit verifies the named owner at
-- runtime; if an owner is removed or renamed, the raw path becomes a hard
-- coverage gap instead of silently falling back to a generated setting.
local CANONICAL_PATH_OWNERS = {
    player = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "player.textRight",
        powerTextMode = "player.powerTextRight",
        anchorMyPoint = "player.point",
        anchorRelPoint = "player.point",
        nameAnchor = "player.nameTextAnchor",
        nameClipSide = "fontScope.shared.shortenNameClipSide",
        nameMaxChars = "fontScope.shared.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.shared.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.shared.shortenNames",
        relativePoint = "player.point",
        shortenNameClipSide = "fontScope.shared.shortenNameClipSide",
        shortenNameMaxChars = "fontScope.shared.shortenNameMaxChars",
        shortenNameShowDots = "fontScope.shared.shortenNameNoEllipsis",
        shortenNames = "fontScope.shared.shortenNames",
    },
    target = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "target.textRight",
        powerTextMode = "target.powerTextRight",
        anchorMyPoint = "target.point",
        anchorRelPoint = "target.point",
        nameAnchor = "target.nameTextAnchor",
        nameClipSide = "fontScope.target.shortenNameClipSide",
        nameMaxChars = "fontScope.target.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.target.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.target.shortenNames",
        relativePoint = "target.point",
        shortenNameShowDots = "fontScope.target.shortenNameNoEllipsis",
    },
    targettarget = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "targettarget.textRight",
        powerTextMode = "targettarget.powerTextRight",
        anchorMyPoint = "targettarget.point",
        anchorRelPoint = "targettarget.point",
        nameAnchor = "targettarget.nameTextAnchor",
        nameClipSide = "fontScope.targettarget.shortenNameClipSide",
        nameMaxChars = "fontScope.targettarget.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.targettarget.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.targettarget.shortenNames",
        relativePoint = "targettarget.point",
        shortenNameShowDots = "fontScope.targettarget.shortenNameNoEllipsis",
    },
    focustarget = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "focustarget.textRight",
        powerTextMode = "focustarget.powerTextRight",
        anchorMyPoint = "focustarget.point",
        anchorRelPoint = "focustarget.point",
        nameAnchor = "focustarget.nameTextAnchor",
        nameClipSide = "fontScope.focustarget.shortenNameClipSide",
        nameMaxChars = "fontScope.focustarget.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.focustarget.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.focustarget.shortenNames",
        relativePoint = "focustarget.point",
        shortenNameShowDots = "fontScope.focustarget.shortenNameNoEllipsis",
    },
    focus = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "focus.textRight",
        powerTextMode = "focus.powerTextRight",
        anchorMyPoint = "focus.point",
        anchorRelPoint = "focus.point",
        nameAnchor = "focus.nameTextAnchor",
        nameClipSide = "fontScope.focus.shortenNameClipSide",
        nameMaxChars = "fontScope.focus.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.focus.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.focus.shortenNames",
        relativePoint = "focus.point",
        shortenNameShowDots = "fontScope.focus.shortenNameNoEllipsis",
    },
    pet = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "pet.textRight",
        powerTextMode = "pet.powerTextRight",
        anchorMyPoint = "pet.point",
        anchorRelPoint = "pet.point",
        nameAnchor = "pet.nameTextAnchor",
        nameClipSide = "fontScope.pet.shortenNameClipSide",
        nameMaxChars = "fontScope.pet.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.pet.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.pet.shortenNames",
        relativePoint = "pet.point",
        shortenNameShowDots = "fontScope.pet.shortenNameNoEllipsis",
    },
    boss = {
        -- Fallback for the RIGHT text slot only: MSUF_UF_Config.lua:1687 reads
        -- conf.textRight first and only then this field, so a write here is
        -- invisible whenever the slot is set, which migration guarantees.
        -- The slot control owns the visible identity.
        hpTextMode = "boss.textRight",
        powerTextMode = "boss.powerTextRight",
        anchorMyPoint = "boss.point",
        anchorRelPoint = "boss.point",
        nameAnchor = "boss.nameTextAnchor",
        nameClipSide = "fontScope.boss.shortenNameClipSide",
        nameMaxChars = "fontScope.boss.shortenNameMaxChars",
        nameNoEllipsis = "fontScope.boss.shortenNameNoEllipsis",
        nameShortenEnabled = "fontScope.boss.shortenNames",
        relativePoint = "boss.point",
        shortenNameShowDots = "fontScope.boss.shortenNameNoEllipsis",
    },
    gf_party = {
        barBgTexture = "barScope.gf_party.barBackgroundTexture",
        -- Legacy 0/1 mirror of the group aggro-border toggle. GetHighlightVal
        -- (MSUF_GroupFrames_DB.lua:1861) reads aggroOutlineMode first and only
        -- falls back to this field, so it is a projection of the reviewed
        -- Party Aggro Border control, never an independent switch.
        hlAggroEnabled = "gf_party.aggroEnabled",
        hpTextMode = "gf_party.textRight",
        hpTextSeparator = "gf_party.textDelimiter",
        nameTextAnchor = "gf_party.nameAnchor",
        point = "gf_party.anchorPoint",
        relativePoint = "gf_party.anchorPoint",
        powerTextSeparator = "gf_party.powerTextDelimiter",
        powerTextMode = "gf_party.powerTextRight",
        shortenNameClipSide = "gf_party.nameClipSide",
        shortenNameMaxChars = "gf_party.nameMaxChars",
        shortenNameShowDots = "gf_party.nameNoEllipsis",
        shortenNames = "gf_party.nameShortenEnabled",
    },
    gf_raid = {
        hlAggroEnabled = "gf_raid.aggroEnabled",
        hpTextMode = "gf_raid.textRight",
        nameTextAnchor = "gf_raid.nameAnchor",
        point = "gf_raid.anchorPoint",
        relativePoint = "gf_raid.anchorPoint",
        powerTextMode = "gf_raid.powerTextRight",
        shortenNameClipSide = "gf_raid.nameClipSide",
        shortenNameMaxChars = "gf_raid.nameMaxChars",
        shortenNameShowDots = "gf_raid.nameNoEllipsis",
        shortenNames = "gf_raid.nameShortenEnabled",
    },
    gf_mythicraid = {
        hlAggroEnabled = "gf_mythicraid.aggroEnabled",
        hpTextMode = "gf_mythicraid.textRight",
        nameTextAnchor = "gf_mythicraid.nameAnchor",
        point = "gf_mythicraid.anchorPoint",
        relativePoint = "gf_mythicraid.anchorPoint",
        powerTextMode = "gf_mythicraid.powerTextRight",
        shortenNameClipSide = "gf_mythicraid.nameClipSide",
        shortenNameMaxChars = "gf_mythicraid.nameMaxChars",
        shortenNameShowDots = "gf_mythicraid.nameNoEllipsis",
        shortenNames = "gf_mythicraid.nameShortenEnabled",
    },
    general = {
        -- Written only as a side effect of the tooltip anchor dropdown
        -- (GlobalMisc.lua:88 derives modern/classic from CURSOR/FIXED),
        -- so the anchor control owns the visible identity.
        unitInfoTooltipStyle = "general.unitTooltipAnchor",
        -- Legacy spelling of the highlight-priority switch. The engine reads
        -- hlPrioEnabled first and only then this alias
        -- (MSUF_UF_Core.lua:542), so the reviewed Custom Highlight Priority
        -- toggle owns the identity.
        highlightPrioEnabled = "general.hlPrioEnabled",
        aggroBorderR = "general.aggroBorderColor",
        aggroBorderG = "general.aggroBorderColor",
        aggroBorderB = "general.aggroBorderColor",
        barBgTexture = "general.barBackgroundTexture",
        barOutlineColorR = "general.barOutlineColor",
        barOutlineColorG = "general.barOutlineColor",
        barOutlineColorB = "general.barOutlineColor",
        castbarFontR = "general.castbarFontColor",
        castbarFontG = "general.castbarFontColor",
        castbarFontB = "general.castbarFontColor",
        castbarInterruptibleR = "general.castbarInterruptibleColor",
        castbarInterruptibleG = "general.castbarInterruptibleColor",
        castbarInterruptibleB = "general.castbarInterruptibleColor",
        castbarNonInterruptibleR = "general.castbarNonInterruptibleColor",
        castbarNonInterruptibleG = "general.castbarNonInterruptibleColor",
        castbarNonInterruptibleB = "general.castbarNonInterruptibleColor",
        healAbsorbBarColorR = "general.healAbsorbBarColor",
        healAbsorbBarColorG = "general.healAbsorbBarColor",
        healAbsorbBarColorB = "general.healAbsorbBarColor",
        healAbsorbBarColorA = "general.healAbsorbBarColor",
        shortenNameShowDots = "fontScope.shared.shortenNameNoEllipsis",
    },
}

-- Exact compatibility fields retained in old/default profile shapes but no
-- longer read by the runtime.  They have no independent Menu2 or Assistant
-- identity.  Keep this review ledger narrow and evidence-backed: unlike a
-- broad name-pattern exclusion, any newly introduced field remains visible to
-- the normal coverage gate.
local COMPATIBILITY_PROJECTIONS = {
    general = {
        castbarPlayerBackendBeforeHide = "Provider memory: the castbar backend remembered while the bar is hidden, restored on unhide.",
        castbarTargetBackendBeforeHide = "Provider memory: the castbar backend remembered while the bar is hidden, restored on unhide.",
        classBarBgA = "Retired class-bar background alpha channel; the live control writes the class-power background color.",
        editModePopupScale = "Edit Mode popup chrome scale persisted by the popup's own grip; it has no Menu2 or Assistant control identity.",
        healPredictionColorR = "Heal-prediction color channel written by the color picker; the curated color control owns the user-facing identity.",
        healPredictionColorG = "Heal-prediction color channel written by the color picker; the curated color control owns the user-facing identity.",
        healPredictionColorB = "Heal-prediction color channel written by the color picker; the curated color control owns the user-facing identity.",
        hpSpacerSelectedUnitKey = "Retired health-spacer scope selector; no runtime or Menu2 consumer reads it, only the default profile still carries the field.",
        hpTextMode = "Legacy shared text-mode seed retained for migration/import; every live UnitFrame and GroupFrame uses its reviewed text-slot controls.",
        powerTextMode = "Legacy shared power-text seed retained for migration/import; every live UnitFrame and GroupFrame uses its reviewed power-text-slot controls.",
        bossCastSpellNameAlign = "Retired castbar spell-text alignment field; SpellNamePosition owns both the anchor and visible alignment.",
        castbarFocusSpellNameAlign = "Retired castbar spell-text alignment field; SpellNamePosition owns both the anchor and visible alignment.",
        castbarPlayerSpellNameAlign = "Retired castbar spell-text alignment field; SpellNamePosition owns both the anchor and visible alignment.",
        castbarTargetSpellNameAlign = "Retired castbar spell-text alignment field; SpellNamePosition owns both the anchor and visible alignment.",
    },
    bars = {
        classPowerOutlineColorR = "Retired class-resource outline color channel; the runtime exposes outline thickness only.",
        classPowerOutlineColorG = "Retired class-resource outline color channel; the runtime exposes outline thickness only.",
        classPowerOutlineColorB = "Retired class-resource outline color channel; the runtime exposes outline thickness only.",
    },
    player = {
        hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
        powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
    },
    target = {
        hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
        powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
    },
    targettarget = {
        hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
        powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
    },
    focus = {
        hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
        powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
    },
    pet = {
        hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
        powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
    },
    boss = {
        hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
        powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer.",
    },
}
local GROUP_COMPATIBILITY_PROJECTIONS = {
    auraSpacing = "Retired flat aura spacing mirror; live group aura geometry uses the nested Buff and Debuff controls.",
    hlBossTargetEnabled = "Retired group boss-target highlight mirror; no runtime or Menu2 code reads it, and the live control is general.bossTargetHighlightEnabled.",
    nameShorten = "Retired pre-normalization group-name shortening field; the canonical group controls own the effective state.",
    nameShortenMax = "Retired pre-normalization group-name length field; the canonical group controls own the effective state.",
    privateAuraAnchor = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    privateAuraCountdown = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    privateAuraMax = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    privateAuraSize = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    privateAuraX = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    privateAuraY = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    privateAurasEnabled = "Retired private-aura layout field with no runtime or Menu2 consumer.",
    shortenNameFrontMaskPx = "Retired unit-only name-mask implementation field; group-frame runtime never consumes it.",
}
local function CopyGroupCompatibilityProjections(includeRetiredTextAnchors)
    local out = {}
    for key, reason in pairs(GROUP_COMPATIBILITY_PROJECTIONS) do out[key] = reason end
    if includeRetiredTextAnchors then
        out.hpTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer."
        out.powerTextAnchor = "Retired saved text-anchor field with no runtime or Menu2 consumer."
    end
    return out
end
COMPATIBILITY_PROJECTIONS.gf_party = CopyGroupCompatibilityProjections(true)
COMPATIBILITY_PROJECTIONS.gf_raid = CopyGroupCompatibilityProjections(true)
COMPATIBILITY_PROJECTIONS.gf_mythicraid = CopyGroupCompatibilityProjections(false)

local GENERATED_EXCLUSIONS = {
    general = {
        disableScaling = true, -- retired migration flag; never a public setting
        globalUiScalePreset = true, -- workflow mirror owned by the curated UI-scale settings/actions
    },
}

local function CanonicalPathOwner(scope, key)
    local scoped = CANONICAL_PATH_OWNERS[scope]
    return scoped and scoped[key] or nil
end
Auto.CanonicalPathOwner = CanonicalPathOwner
Auto.CanonicalPathOwners = CANONICAL_PATH_OWNERS

local function CompatibilityProjectionReason(scope, key)
    local scoped = COMPATIBILITY_PROJECTIONS[scope]
    return scoped and scoped[key] or nil
end
Auto.CompatibilityProjectionReason = CompatibilityProjectionReason
Auto.CompatibilityProjections = COMPATIBILITY_PROJECTIONS

local function IsGeneratedPathAllowed(scope, key)
    local excluded = GENERATED_EXCLUSIONS[scope]
    return not ((excluded and excluded[key] == true)
        or CanonicalPathOwner(scope, key) ~= nil
        or CompatibilityProjectionReason(scope, key) ~= nil)
end
Auto.IsGeneratedPathAllowed = IsGeneratedPathAllowed

-- Adds reviewed raw-path ownership to a CoverageAudit result without mutating
-- the public registry descriptors.  This keeps the storage ledger centralized
-- in AutoCoverage and makes owner drift fail closed: an absent owner is not
-- claimed and will remain a visible DB coverage gap.
function Auto.ApplyCanonicalPathOwnership(covered, Registry)
    if type(covered) ~= "table" or type(Registry) ~= "table"
        or type(Registry.GetSetting) ~= "function" then return 0, 0 end
    local Audit = A.CoverageAudit
    local NormalizeKey = Audit and Audit.NormalizeCoverageKey
        or function(value) return tostring(value or ""):lower():gsub("[^%w]", "") end
    local claimed, missing = 0, 0
    for scope, paths in pairs(CANONICAL_PATH_OWNERS) do
        local scopeSet = covered[scope]
        if not scopeSet then
            scopeSet = { _norm = {} }
            covered[scope] = scopeSet
        elseif type(scopeSet._norm) ~= "table" then
            scopeSet._norm = {}
        end
        for dbKey, ownerKey in pairs(paths) do
            local owner = Registry:GetSetting(ownerKey)
            if type(owner) == "table" and owner.generated ~= true then
                scopeSet[dbKey] = owner
                scopeSet._norm[NormalizeKey(dbKey)] = owner
                claimed = claimed + 1
            else
                missing = missing + 1
            end
        end
    end
    Auto.lastCanonicalOwnershipClaimed = claimed
    Auto.lastCanonicalOwnershipMissing = missing
    return claimed, missing
end

-- "Channel" keeps these distinct from color VALUE words ("set X color to red")
-- that the color parser owns.
local CHANNEL_WORDS = { R = "Red Channel", G = "Green Channel", B = "Blue Channel", A = "Alpha Channel" }

-- Detect a generated number that is one channel of a composite color (a DB key
-- ending in R/G/B/A whose stem is a color concept).  MSUF exposes colors through
-- color pickers, never per-channel sliders, so a user who says "set X color to
-- black" means the whole color.  These channel scalars are kept in the registry
-- for DB coverage but are marked so the Assistant never treats a single channel
-- as a mutation target for a color value.
local COLOR_CHANNEL_STEM_WORDS = {
    "color", "colour", "background", "border", "bg", "gradient", "aggro",
    "namecolor", "glow", "tick", "altmana", "absorb", "highlight", "hl",
}

-- scope -> { stem = true } for every stem the manifest proves is a composite
-- color by carrying the whole R, G and B sibling set in that scope. Three
-- sibling numbers differing only by an R/G/B suffix are a color by
-- construction, so this needs no vocabulary. The word list below stays as the
-- fallback for live-DB paths the manifest never saw, but it cannot be kept
-- complete by hand: castbarText, unifiedBar, fontR/G/B, classPowerRampStart
-- and targetedSpellsText* are all real colors whose names contain none of its
-- words, and each one used to be published as an unbounded standalone number.
local colorTripletStems = {}

local function NoteColorTripletStems(scope, keys)
    local channels = {}
    for i = 1, #keys do
        local key = keys[i]
        local channel = key:match("([RGBA])$")
        if channel then
            local stem = key:sub(1, #key - 1)
            if stem ~= "" and stem:sub(-1):match("[%l%d]") then
                local seen = channels[stem]
                if not seen then seen = {}; channels[stem] = seen end
                seen[channel] = true
            end
        end
    end
    local stems = {}
    for stem, seen in pairs(channels) do
        if seen.R and seen.G and seen.B then stems[stem] = true end
    end
    colorTripletStems[scope] = stems
    return stems
end

local function IsColorChannelKey(key, scope)
    key = tostring(key or "")
    local channel = key:match("([RGBA])$")
    if not channel then return nil end
    -- The character before the channel letter must be a lowercase letter or a
    -- digit, so real words ending in an uppercase R/G/B/A are not misread.
    local prev = key:sub(-2, -2)
    if not prev:match("[%l%d]") then return nil end
    local stem = key:sub(1, #key - 1)
    local proven = scope and colorTripletStems[scope]
    if proven and proven[stem] then return channel end
    local lowerStem = stem:lower()
    for i = 1, #COLOR_CHANNEL_STEM_WORDS do
        if lowerStem:find(COLOR_CHANNEL_STEM_WORDS[i], 1, true) then return channel end
    end
    return nil
end
Auto.IsColorChannelKey = IsColorChannelKey

local function LabelFromKey(key)
    local label = key:gsub("(%l)(%u)", "%1 %2")
        -- Acronym boundary: "alphaBGOutOfCombat" -> "alpha BG Out Of Combat",
        -- not "alpha BGOut Of Combat".
        :gsub("(%u)(%u%l)", "%1 %2")
        :gsub("(%a)(%d)", "%1 %2"):gsub("_", " ")
    -- Trailing color channel letters make aliases ambiguous once text
    -- normalization drops single-character tokens; spell them out.
    label = label:gsub(" ([RGBA])$", function(c) return " " .. CHANNEL_WORDS[c] end)
    return (label:gsub("^%l", string.upper))
end

local function LabelFromPath(path)
    local labels = {}
    for segment in tostring(path or ""):gmatch("[^.]+") do
        labels[#labels + 1] = LabelFromKey(segment)
    end
    return table.concat(labels, " ")
end

local function ScopeLabel(scope)
    local RC = A.RegistryCore
    local labels = RC and RC.UNIT_LABELS or {}
    if GROUP_SCOPES[scope] then return labels[GROUP_SCOPES[scope]] or LabelFromKey(GROUP_SCOPES[scope]) end
    return labels[scope] or LabelFromKey(scope)
end

local function KeyHas(lkey, needle)
    return lkey:find(needle, 1, true) ~= nil
end

local function KeyHasAny(lkey, list)
    for i = 1, #list do
        if KeyHas(lkey, list[i]) then return true end
    end
    return false
end

local function KeyIsDetachedPower(lkey)
    return KeyHas(lkey, "detachedpower") or KeyHas(lkey, "powerbardetached")
end

local COLOR_KEY_TERMS = {
    "color", "colour", "tint",
}
local CASTBAR_KEY_TERMS = {
    "castbar", "focuskick", "kickready", "kicknotready",
}
local CLASSPOWER_KEY_TERMS = {
    "classpower", "combo", "runeshow", "altmana", "ebonmight", "maelstrom",
}
local AURA_KEY_TERMS = {
    "aura", "buff", "debuff", "pandemic",
}
local FONT_KEY_TERMS = {
    "font", "text", "name", "label",
}
local ALPHA_KEY_TERMS = {
    "alpha", "opacity", "fade", "transparency", "rangefade",
}
local BAR_KEY_TERMS = {
    "bar", "border", "outline", "texture", "gradient", "smooth", "absorb", "healprediction", "healabsorb",
}
local GROUP_GEOMETRY_KEY_TERMS = {
    "growth", "sort",
    "width", "height", "scale", "spacing", "padding", "offset", "layout",
    "columns", "rows", "perrow", "percolumn", "unitsper", "groupsper",
}
local GROUP_REBUILD_EXACT_KEYS = {
    enabled = true,
    showSolo = true,
    showParty = true,
    showRaid = true,
    showInRaid = true,
    showInParty = true,
    hideInClientScene = true,
    hideInHousing = true,
    hideInCombat = true,
    hideOutOfCombat = true,
    hideInInstance = true,
}
local GROUP_VISUAL_KEY_TERMS = {
    "raidmarker", "groupnumber", "roleicon", "leadericon", "assisticon",
    "readycheck", "summon", "resurrect", "pvpicon", "phaseicon",
    "statustext", "iconstyle", "customicon", "icon", "indicator",
    "cornerindicator", "spellindicator", "cienabled", "cislot", "cisize", "cialpha", "cicustom",
    "hlfocus", "hltarget", "highlight", "healthfade", "health", "power",
}
local GROUP_BORDER_KEY_TERMS = {
    "border", "outline", "aggro", "dispel", "purge", "stripe",
}
local MENU_ONLY_KEY_TERMS = {
    "tooltip", "locale", "menu", "navhover", "dropdownstyle", "blizzard",
}

local function CallApply(fn, reason)
    if type(fn) ~= "function" then return nil end
    return function() fn(reason) end
end

local function CurrentApplyService()
    return (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
end

local function CastbarUnitForKey(key)
    key = tostring(key or "")
    local castbars = A.CastbarsRegistry
    local tables = {
        castbars and castbars.CASTBAR_KEYS,
        castbars and castbars.CASTBAR_DETAIL_FIELDS,
        A.RegistryCore and A.RegistryCore.CASTBAR_KEYS,
        A.RegistryCore and A.RegistryCore.CASTBAR_DETAIL_FIELDS,
    }
    for i = 1, #tables do
        local byUnit = tables[i]
        if type(byUnit) == "table" then
            for unit, keys in pairs(byUnit) do
                if type(keys) == "table" then
                    for _, dbKey in pairs(keys) do
                        if dbKey == key then return unit end
                    end
                end
            end
        end
    end
    local lkey = key:lower()
    if lkey:find("playercast", 1, true) or lkey:find("castbarplayer", 1, true) then return "player" end
    if lkey:find("targetcast", 1, true) or lkey:find("castbartarget", 1, true) then return "target" end
    if lkey:find("focuscast", 1, true) or lkey:find("castbarfocus", 1, true) or lkey:find("focuskick", 1, true) then return "focus" end
    if lkey:find("bosscast", 1, true) or lkey:find("castbarboss", 1, true) then return "boss" end
    return nil
end

local function GeneralFlagApply(RC, reason, opts)
    return function()
        RC.ApplyGeneral(reason, opts)
    end
end

local function GeneralScopeApply(RC, key)
    local reason = "MSUF_ASSISTANT_AUTO_" .. key
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    local isColor = KeyHasAny(lkey, COLOR_KEY_TERMS) or keyText:match("[RGBA]$") ~= nil
    local isCastbar = KeyHasAny(lkey, CASTBAR_KEY_TERMS)
    local isClassPower = KeyHasAny(lkey, CLASSPOWER_KEY_TERMS)
    local isAura = KeyHasAny(lkey, AURA_KEY_TERMS)
    local isPortrait = KeyHas(lkey, "portrait")

    local castbarUnit = isCastbar and CastbarUnitForKey(keyText) or nil

    if isCastbar and isColor then
        if type(RC.ApplyCastbarColors) == "function" then return function() RC.ApplyCastbarColors(reason, castbarUnit) end end
        if type(RC.ApplyCastbar) == "function" then return function() RC.ApplyCastbar(reason, castbarUnit) end end
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, castbar = true, castbarTextures = true })
    end
    if isClassPower and isColor then return CallApply(RC.ApplyClassPowerColors, reason) or CallApply(RC.ApplyClassPower, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, classpower = true }) end
    if isAura and isColor then return CallApply(RC.ApplyAuraColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, colors = true }) end
    if isPortrait and isColor then return CallApply(RC.ApplyPortraitColors, reason) or CallApply(RC.ApplyColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, colors = true }) end
    if isColor then return CallApply(RC.ApplyColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, colors = true }) end
    if isCastbar then
        if type(RC.ApplyCastbar) == "function" then return function() RC.ApplyCastbar(reason, castbarUnit) end end
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, castbar = true, castbarTextures = true })
    end
    if isClassPower then return CallApply(RC.ApplyClassPower, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, classpower = true }) end
    if isAura and type(RC.ApplyAura) == "function" then
        return function() RC.ApplyAura("shared", reason) end
    end
    if isPortrait then return CallApply(RC.ApplyPortraitColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, visual = true }) end
    if KeyHasAny(lkey, FONT_KEY_TERMS) then return CallApply(RC.ApplyFonts, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, fonts = true }) end
    if KeyHasAny(lkey, ALPHA_KEY_TERMS) then
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, alpha = true, bars = true })
    end
    if KeyHas(lkey, "power") then
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, power = true, bars = true })
    end
    if KeyHasAny(lkey, BAR_KEY_TERMS) then return CallApply(RC.ApplyBars, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, bars = true }) end
    if KeyHasAny(lkey, MENU_ONLY_KEY_TERMS) then
        return GeneralFlagApply(RC, reason, { preview = false, applyAll = false, notify = false })
    end
    return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, visual = true })
end

local function GroupModeForKey(key)
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    if KeyHasAny(lkey, AURA_KEY_TERMS) then return "auras" end
    if KeyHasAny(lkey, FONT_KEY_TERMS) then return "fonts" end
    if KeyHasAny(lkey, GROUP_BORDER_KEY_TERMS) then return "border" end
    if KeyHasAny(lkey, COLOR_KEY_TERMS) or keyText:match("[RGBA]$") ~= nil then return "colors" end
    if KeyHasAny(lkey, GROUP_VISUAL_KEY_TERMS) then return "visual" end
    if GROUP_REBUILD_EXACT_KEYS[keyText] then return "rebuild" end
    if KeyHasAny(lkey, GROUP_GEOMETRY_KEY_TERMS) then return "geometry" end
    if KeyHasAny(lkey, BAR_KEY_TERMS) or KeyHasAny(lkey, ALPHA_KEY_TERMS) then return "visual" end
    return "visual"
end

local function UnitApplyOptsForKey(key)
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    local opts = { preview = true }
    if KeyHasAny(lkey, FONT_KEY_TERMS) then opts.text = true end
    if KeyIsDetachedPower(lkey) then
        opts.power = true
        opts.detachedPowerBar = true
    elseif KeyHas(lkey, "power") then
        opts.power = true
    end
    if KeyHasAny(lkey, ALPHA_KEY_TERMS) then opts.alpha = true end
    if KeyHasAny(lkey, CASTBAR_KEY_TERMS) then opts.castbar = true end
    if KeyHasAny(lkey, AURA_KEY_TERMS) then opts.auras = true end
    return opts
end

local function DirtyMaskForGroupMode(gf, mode)
    if type(gf) ~= "table" then return nil end
    if mode == "fonts" or mode == "font" then return gf.DIRTY_FONT end
    if mode == "colors" or mode == "color" then return gf.DIRTY_COLOR end
    if mode == "border" or mode == "borders" then return gf.DIRTY_BORDER end
    if mode == "auras" then return gf.DIRTY_AURAS end
    if mode == "geometry" then
        local dirty = tonumber(gf.DIRTY_GEOMETRY) or 0
        local layout = tonumber(gf.DIRTY_LAYOUT) or 0
        dirty = dirty + layout
        return dirty ~= 0 and dirty or gf.DIRTY_VISUAL
    end
    return gf.DIRTY_VISUAL
end

local function ApplyLegacyGroupScope(groupScope, mode, dirty)
    if type(groupScope) ~= "string" or groupScope == "" then return false end
    local did = false
    if mode == "rebuild" then
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(groupScope); did = true end
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then _G.MSUF_GF_RefreshUnitBindings(groupScope); did = true end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals(groupScope, dirty); did = true end
        return did
    end
    if mode == "geometry" then
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(groupScope); did = true end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals(groupScope, dirty); did = true end
        return did
    end
    if type(_G.MSUF_GF_RefreshVisuals) == "function" then
        _G.MSUF_GF_RefreshVisuals(groupScope, dirty)
        return true
    end
    return false
end

local function FallbackFlatApplyOptions(scope, key)
    local opts = { preview = true, applyAll = false }
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    if KeyIsDetachedPower(lkey) then
        opts.power = true
        opts.detachedPowerBar = true
        opts.classpower = true
    elseif scope == "bars" or KeyHasAny(lkey, BAR_KEY_TERMS) then
        opts.bars = true
    elseif KeyHasAny(lkey, COLOR_KEY_TERMS) or keyText:match("[RGBA]$") ~= nil then
        opts.colors = true
    elseif KeyHasAny(lkey, CASTBAR_KEY_TERMS) then
        opts.castbar = true
        opts.castbarTextures = true
    elseif KeyHasAny(lkey, CLASSPOWER_KEY_TERMS) then
        opts.classpower = true
    elseif KeyHasAny(lkey, FONT_KEY_TERMS) then
        opts.fonts = true
    elseif KeyHasAny(lkey, ALPHA_KEY_TERMS) then
        opts.alpha = true
    elseif KeyHas(lkey, "power") then
        opts.power = true
        opts.bars = true
    elseif KeyHasAny(lkey, MENU_ONLY_KEY_TERMS) then
        opts.preview = false
        opts.notify = false
    end
    return opts
end

local function FallbackScopeApply(scope, key)
    if UNIT_SCOPES[scope] then
        local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or scope)
        return function()
            if M and type(M.RequestUnitApply) == "function" then
                return M.RequestUnitApply(scope, reason, UnitApplyOptsForKey(key))
            end
            local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
            if apply and type(apply.RequestUnit) == "function" then
                return apply.RequestUnit(scope, reason, UnitApplyOptsForKey(key))
            end
            if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
                return _G.MSUF_UFCore_NotifyConfigChanged(scope, true, true, reason)
            end
        end
    end
    if GROUP_SCOPES[scope] then
        local groupScope = GROUP_SCOPES[scope]
        local mode = GroupModeForKey(key)
        return function()
            local apply = CurrentApplyService()
            local gf = MSUF and MSUF.GF
            local dirty = DirtyMaskForGroupMode(gf, mode)
            local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or groupScope)
            if mode ~= "rebuild" and mode ~= "reset" and dirty and apply and type(apply.RequestGroupDirtyMask) == "function" then
                return apply.RequestGroupDirtyMask(groupScope, dirty, reason)
            end
            if apply and type(apply.RequestGroup) == "function" then
                return apply.RequestGroup(groupScope, mode, reason)
            end
            if dirty and apply and type(apply.RequestGroupDirtyMask) == "function" then
                return apply.RequestGroupDirtyMask(groupScope, dirty, reason)
            end
            local GP = M and M.GroupPage
            if GP and type(GP.QueueGF) == "function" then
                return GP.QueueGF(groupScope, mode)
            end
            if ApplyLegacyGroupScope(groupScope, mode, dirty) then return true end
            if mode == "rebuild" and type(_G.MSUF_GF_RefreshAll) == "function" then return _G.MSUF_GF_RefreshAll() end
        end
    end
    if FLAT_SCOPES[scope] then
        local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or scope)
        local opts = FallbackFlatApplyOptions(scope, key)
        return function()
            local apply = CurrentApplyService()
            if M and type(M.RequestGeneralApply) == "function" then
                return M.RequestGeneralApply(reason, opts)
            end
            if apply and type(apply.RequestGeneral) == "function" then
                return apply.RequestGeneral(reason, opts)
            end
            if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
                return _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)
            end
        end
    end
    return function()
        local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or scope or "fallback")
        if M and type(M.RequestGeneralApply) == "function" then
            return M.RequestGeneralApply(reason, { preview = true, applyAll = true, frames = true })
        end
        local apply = CurrentApplyService()
        if apply and type(apply.RequestGeneral) == "function" then
            return apply.RequestGeneral(reason, { preview = true, applyAll = true, frames = true })
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            return _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)
        end
    end
end

local function ScopeApply(scope, key)
    local RC = A.RegistryCore
    if not RC then return FallbackScopeApply(scope, key) end
    if UNIT_SCOPES[scope] and type(RC.ApplyUnit) == "function" then
        local reason = "MSUF_ASSISTANT_AUTO_" .. key
        return function() RC.ApplyUnit(scope, reason, UnitApplyOptsForKey(key)) end
    end
    if GROUP_SCOPES[scope] and type(RC.ApplyGroup) == "function" then
        local groupScope = GROUP_SCOPES[scope]
        local mode = GroupModeForKey(key)
        return function() RC.ApplyGroup(groupScope, mode) end
    end
    if scope == "general" and type(RC.ApplyGeneral) == "function" then
        return GeneralScopeApply(RC, key)
    end
    local flat = {
        bars = RC.ApplyBars,
        gameplay = RC.ApplyGameplay,
    }
    local fn = flat[scope]
    if type(fn) == "function" then
        local reason = "MSUF_ASSISTANT_AUTO_" .. key
        return function() fn(reason) end
    end
    return FallbackScopeApply(scope, key)
end

local function ScopeTable(scope, create)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    local tbl = db[scope]
    if type(tbl) ~= "table" and create then
        tbl = {}
        db[scope] = tbl
    end
    return type(tbl) == "table" and tbl or nil
end

local MAX_NESTED_DEPTH = 8

local function PathSegments(path)
    local out = {}
    for segment in tostring(path or ""):gmatch("[^.]+") do
        if segment == "" or segment:sub(1, 1) == "_" or segment:match("^%d+$") then return nil end
        out[#out + 1] = segment
        if #out > MAX_NESTED_DEPTH then return nil end
    end
    return #out > 0 and out or nil
end

local function PathValue(root, path)
    local segments = type(path) == "table" and path or PathSegments(path)
    if type(root) ~= "table" or not segments then return nil, false end
    local node = root
    for i = 1, #segments - 1 do
        node = node[segments[i]]
        if type(node) ~= "table" then return nil, false end
    end
    local value = node[segments[#segments]]
    return value, value ~= nil
end

local function WritePath(root, path, value, create)
    local segments = type(path) == "table" and path or PathSegments(path)
    if type(root) ~= "table" or not segments then return false end
    local node = root
    for i = 1, #segments - 1 do
        local child = node[segments[i]]
        if type(child) ~= "table" then
            if not create or child ~= nil then return false end
            child = {}
            node[segments[i]] = child
        end
        node = child
    end
    node[segments[#segments]] = value
    return true
end

local function IsSafePath(Audit, scope, path)
    local segments = PathSegments(path)
    if not segments then return false end
    if Audit and type(Audit.IsIgnored) == "function" then
        if Audit.IsIgnored(scope, segments[1]) or Audit.IsIgnored(scope, path) then return false end
    end
    return true
end

local SortedKeys

local function WalkScalarPaths(root, callback)
    if type(root) ~= "table" or type(callback) ~= "function" then return end
    local keys = SortedKeys(root)
    for i = 1, #keys do
        local key = keys[i]
        if type(key) == "string" and key ~= "" and key:sub(1, 1) ~= "_"
            and not key:match("^%d+$") and not key:find(".", 1, true)
        then
            local value = root[key]
            local valueType = type(value)
            if valueType == "boolean" or valueType == "number" or valueType == "string" then
                callback(key, value)
            end
        end
    end
end

local function ManifestDefaults()
    local manifest = A.AutoCoverageManifest
    if type(manifest) ~= "table" then return nil end
    if type(manifest.defaults) == "table" then return manifest.defaults end
    return manifest
end

-- Word-level synonyms so generated settings answer to human phrasing, not just
-- the camelCase-derived label ("hp bg alpha" -> "health background opacity").
-- Keys are single lowercase label words; each maps to alternative words.
-- English only. Kept small on purpose: every synonym multiplies alias variants.
local WORD_SYNONYMS = {
    alpha = { "opacity", "transparency" },
    bg = { "background" },
    background = { "bg" },
    tex = { "texture" },
    hp = { "health", "health bar" },
    pos = { "position" },
    dist = { "distance" },
    sep = { "separator" },
    icon = { "symbol" },
    -- no "colour": text normalization canonicalizes it to "color" anyway, so
    -- the variant would only duplicate index entries.
}
local MAX_GENERATED_ALIASES = 12

local function AddAliasVariants(aliases, seen, base)
    local function add(text)
        if #aliases >= MAX_GENERATED_ALIASES then return end
        if text ~= "" and not seen[text] then
            seen[text] = true
            aliases[#aliases + 1] = text
        end
    end
    add(base)
    -- One-word substitutions: replace each synonym-bearing word once so variant
    -- count stays linear, not combinatorial.
    for word in base:gmatch("%S+") do
        local subs = WORD_SYNONYMS[word]
        if subs then
            for i = 1, #subs do
                add((base:gsub("%f[%w]" .. word .. "%f[%W]", subs[i], 1)))
            end
        end
    end
end

-- Legacy mirror keys ("portraitBgColorR" alongside "portraitBackgroundColorR")
-- collapse into one generated setting; set() keeps every mirror in sync since
-- we cannot know statically which spelling the runtime reads.
local function WriteMirrors(spec, tbl, v)
    local mirrors = spec and spec.mirrorKeys
    if mirrors and tbl then
        for i = 1, #mirrors do WritePath(tbl, mirrors[i], v, true) end
    end
end

-- A few flat manifest keys have deliberately player-facing menu labels that do
-- not resemble their storage names.  Keep generated Assistant output aligned
-- with the actual control instead of exposing implementation labels such as
-- "General Hard Kill Blizzard Player Frame".
local GENERATED_LABEL_OVERRIDES = {
    ["general.disableBlizzardUnitFrames"] = "Disable Blizzard Unit Frames",
    ["general.hardKillBlizzardPlayerFrame"] = "Fully Hide Blizzard PlayerFrame - resource bar compatibility",
}

local function BuildSpec(scope, key, value, fromManifest)
    local valueType = type(value)
    local overrideLabel = GENERATED_LABEL_OVERRIDES[scope .. "." .. key]
    local label = overrideLabel or LabelFromPath(key)
    local scopeLabel = ScopeLabel(scope)
    local fullLabel = overrideLabel or (scopeLabel .. " " .. label)
    local aliasBase = label:lower()
    local aliases, seen = {}, {}
    local function AddPriorityAlias(alias)
        if alias ~= "" and not seen[alias] then
            seen[alias] = true
            table.insert(aliases, 1, alias)
        end
    end
    if FLAT_SCOPES[scope] then
        -- Flat scopes have no unit word in the sentence to disambiguate them;
        -- lead with the scope-prefixed phrase so "gameplay font size" and
        -- "general font size" stay distinct for prompt generation.
        AddAliasVariants(aliases, seen, fullLabel:lower())
        AddAliasVariants(aliases, seen, aliasBase)
    else
        AddAliasVariants(aliases, seen, aliasBase)
        AddAliasVariants(aliases, seen, fullLabel:lower())
    end
    if scope == "general" and key == "disableBlizzardUnitFrames" then
        AddPriorityAlias("blizzard unitframes")
    elseif scope == "general" and key == "hardKillBlizzardPlayerFrame" then
        AddPriorityAlias("hard hide blizzard player frame")
        AddPriorityAlias("fully hide blizzard player frame")
        AddPriorityAlias("blizzard player frame")
    end
    local unit = UNIT_SCOPES[scope] and scope or GROUP_SCOPES[scope] or nil
    local spec = {
        key = scope .. "." .. key,
        label = fullLabel,
        category = scopeLabel .. " / Auto (generated)",
        unit = unit,
        frameType = GROUP_SCOPES[scope] and "group" or (UNIT_SCOPES[scope] and "unitframe" or scope),
        attribute = key,
        dbPath = key,
        generatedNested = false,
        aliases = aliases,
        generated = true,
        -- Keep false as a real default; the common `a and value or nil`
        -- idiom would erase boolean-off manifest values.
        manifestDefault = value,
        manifestBacked = fromManifest == true,
        combatSafe = false,
        apply = ScopeApply(scope, key),
        description = fromManifest
            and ("Auto-generated from the default manifest; controls '" .. key .. "' directly.")
            or ("Auto-generated from saved settings; controls '" .. key .. "' directly."),
    }
    if valueType == "boolean" then
        spec.type = "boolean"
        spec.generatedMutationSafety = "boolean"
        spec.assistantMutationSafe = true
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v, exists = PathValue(tbl, key)
            if not exists then return value and true or false end
            return v and true or false
        end
        spec.set = function(v)
            local tbl = ScopeTable(scope, true)
            if tbl then
                WritePath(tbl, key, v and true or false, true)
                WriteMirrors(spec, tbl, v and true or false)
            end
        end
    elseif valueType == "number" then
        spec.type = "number"
        -- A default value is evidence for the current value, not for the
        -- control's domain.  In particular, a default in [0, 1] may be an
        -- alpha, a scale with a wider range, an enum encoded as a number, or a
        -- counter.  Keep every generated number read-only until a curated
        -- registry entry supplies reviewed min/max/step metadata.
        spec.step = 1
        spec.generatedMutationSafety = "unreviewed-number-domain"
        spec.assistantMutationSafe = false
        spec.unsafeMutationReason = "This generated numeric setting has no reviewed minimum, maximum, or step."
        -- One channel of a composite color.  Flag it so a color-value request
        -- never resolves to a single channel; MSUF colors are set through a
        -- color picker, so this points the user there instead.
        if IsColorChannelKey(key, scope) then
            spec.assistantColorChannel = true
            spec.generatedMutationSafety = "color-channel-component"
            -- The example has to be typeable. scopeLabel is the English name
            -- the player sees ("Party"); the raw scope token ("gf_party") is
            -- not something they would ever enter.
            spec.unsafeMutationReason = "This is one channel of a composite color. Set the whole color instead, for example 'set " .. string.lower(scopeLabel) .. " color to red'."
        end
        spec.get = function()
            local tbl = ScopeTable(scope)
            local raw = PathValue(tbl, key)
            local v = tonumber(raw)
            if v == nil then return value end
            return v
        end
        spec.set = function(v)
            v = tonumber(v)
            if v == nil then return end
            if spec.min and v < spec.min then v = spec.min end
            if spec.max and v > spec.max then v = spec.max end
            local tbl = ScopeTable(scope, true)
            if tbl then
                WritePath(tbl, key, v, true)
                WriteMirrors(spec, tbl, v)
            end
        end
    else
        spec.type = "string"
        spec.generatedMutationSafety = "unconstrained-string"
        spec.assistantMutationSafe = false
        spec.unsafeMutationReason = "This generated string setting has no reviewed list of allowed values."
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v, exists = PathValue(tbl, key)
            if not exists then return value end
            return tostring(v)
        end
        spec.set = function(v)
            local tbl = ScopeTable(scope, true)
            if tbl then
                WritePath(tbl, key, tostring(v), true)
                WriteMirrors(spec, tbl, tostring(v))
            end
        end
    end
    return spec
end

SortedKeys = function(map)
    local out = {}
    if type(map) ~= "table" then return out end
    for key in pairs(map) do
        if type(key) == "string" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

local function LuaString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub('"', '\\"')
    return '"' .. value .. '"'
end

local function LuaKey(key)
    key = tostring(key or "")
    if key:match("^[%a_][%w_]*$") then return key end
    return "[" .. LuaString(key) .. "]"
end

local function LuaValue(value)
    local valueType = type(value)
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType == "number" then return tostring(value) end
    return LuaString(value)
end

local function AllManifestScopes()
    local scopes = {}
    for scope in pairs(UNIT_SCOPES) do scopes[#scopes + 1] = scope end
    for scope in pairs(GROUP_SCOPES) do scopes[#scopes + 1] = scope end
    for scope in pairs(FLAT_SCOPES) do scopes[#scopes + 1] = scope end
    table.sort(scopes)
    return scopes
end

function Auto.BuildManifestText()
    local Audit = A.CoverageAudit
    local lines = {
        "-- Paste into MSUF_AssistantRegistry_AutoCoverage_Manifest.lua.",
        "-- Source: freshly seeded profile DB safe scalar paths.",
        "Manifest.defaults = {",
    }
    local scopes = AllManifestScopes()
    local total = 0
    for i = 1, #scopes do
        local scope = scopes[i]
        local tbl = ScopeTable(scope)
        local wroteScope = false
        WalkScalarPaths(tbl, function(key, value)
            if IsSafePath(Audit, scope, key) then
                if not wroteScope then
                    lines[#lines + 1] = "    " .. LuaKey(scope) .. " = {"
                    wroteScope = true
                end
                -- Dotted keys keep the export compact and remain backwards
                -- compatible with the existing flat manifest format.
                lines[#lines + 1] = "        " .. LuaKey(key) .. " = " .. LuaValue(value) .. ","
                total = total + 1
            end
        end)
        if wroteScope then lines[#lines + 1] = "    }," end
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("-- safe scalar paths: %d"):format(total)
    return table.concat(lines, "\n"), total
end

function Auto.StoreManifestExport(text, total)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    gdb.assistantAutoCoverageManifest = {
        time = date("%Y-%m-%d %H:%M:%S"),
        total = tonumber(total) or 0,
        text = tostring(text or ""),
    }
end

--- Registers generated settings for every uncovered safe scalar DB path.
--- Returns the number of settings added (0 when everything is covered or
--- prerequisites are missing). Safe to call repeatedly.
function Auto.Fill()
    local Registry = A.Registry
    if not (Registry and type(Registry.RegisterSetting) == "function") then return 0 end
    local Audit = A.CoverageAudit
    if not (Audit and type(Audit.BuildCoveredSets) == "function") then return 0 end
    local covered = Audit.BuildCoveredSets()
    local added = 0
    local fillWork = 0
    local IsCoveredKey = Audit.IsCoveredKey or function(set, k) return set[k] end
    local NormalizeKey = Audit.NormalizeCoverageKey or function(k) return k end
    -- normKey -> generated spec, per scope: legacy mirror spellings of the
    -- same field collapse into one setting instead of colliding as aliases.
    local generatedByNorm = {}
    local function RegisterGenerated(scope, key, value, coveredSet, fromManifest)
        fillWork = fillWork + 1
        if fillWork % 64 == 0 and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local valueType = type(value)
        if type(key) == "string"
            and not key:find(".", 1, true)
            and IsGeneratedPathAllowed(scope, key)
            and IsSafePath(Audit, scope, key)
            and not IsCoveredKey(coveredSet, key)
            and (valueType == "boolean" or valueType == "number" or valueType == "string")
        then
            local fullKey = scope .. "." .. key
            local existing = type(Registry.GetSetting) == "function" and Registry:GetSetting(fullKey) or nil
            if existing then
                coveredSet[key] = existing
                return
            end
            local normMap = generatedByNorm[scope]
            if not normMap then
                normMap = {}
                generatedByNorm[scope] = normMap
            end
            local norm = NormalizeKey(key)
            local twin = normMap[norm]
            if twin then
                twin.mirrorKeys = twin.mirrorKeys or {}
                twin.mirrorKeys[#twin.mirrorKeys + 1] = key
                coveredSet[key] = twin
                return
            end
            local registered = Registry:RegisterSetting(BuildSpec(scope, key, value, fromManifest))
            if registered then
                coveredSet[key] = registered
                normMap[norm] = registered
                added = added + 1
            end
        end
    end

    local function FillManifestScope(scope)
        local manifest = ManifestDefaults()
        local manifestScope = type(manifest) == "table" and manifest[scope] or nil
        if type(manifestScope) ~= "table" then return end
        local coveredSet = covered[scope] or {}
        covered[scope] = coveredSet
        -- Learn this scope's proven color triplets before any spec is built:
        -- BuildSpec must already know that "fontR" is a channel and not a
        -- standalone unbounded number.
        local scopeKeys = {}
        WalkScalarPaths(manifestScope, function(key)
            if not key:find(".", 1, true) then scopeKeys[#scopeKeys + 1] = key end
        end)
        NoteColorTripletStems(scope, scopeKeys)
        WalkScalarPaths(manifestScope, function(key, value)
            -- The checked-in factory manifest is the identity authority.
            -- Saved profiles may contain legacy or future fields, but those
            -- cannot create environment-dependent public Assistant controls.
            RegisterGenerated(scope, key, value, coveredSet, true)
        end)
    end
    for scope in pairs(UNIT_SCOPES) do FillManifestScope(scope) end
    for scope in pairs(GROUP_SCOPES) do FillManifestScope(scope) end
    for scope in pairs(FLAT_SCOPES) do FillManifestScope(scope) end
    Auto.lastFillCount = added
    Auto.lastNestedFillCount = 0
    -- Promote generated numbers to a safe write domain wherever a reviewed
    -- curated sibling supplies one.  Runs after every generated spec is
    -- registered so the curated/generated split is fully visible.
    Auto.PromoteInheritedNumberDomains()
    Auto.PromoteInheritedValueLists()
    Auto.PromoteReviewedMediaTypes()
    Auto._fillComplete = true
    return added
end

-- Generic leaf names that describe a property of many unrelated controls
-- (a portrait "size" is not a font "size").  Even when every curated setting
-- that happens to share such a leaf agrees on a domain today, that agreement
-- is coincidental, so a generic leaf is never a safe promotion source.
local UNSAFE_PROMOTION_LEAVES = {
    size = true, width = true, height = true, x = true, y = true,
    offsetX = true, offsetY = true, offsetx = true, offsety = true,
    alpha = true, scale = true, layer = true, thickness = true,
    spacing = true, padding = true, length = true, opacity = true,
    r = true, g = true, b = true, a = true,
}

local function PromotionLeaf(key)
    return tostring(key or ""):match("([^.]+)$") or ""
end

-- Reviewed write domains transcribed from the Menu2 slider that owns each
-- field. These are not estimates: the options page binds the control with an
-- explicit range, e.g.
--   BindSlider(positive, "Bar height (0 = full)", 0, 100, 1, "absorbBarHeight", 0, ...)
-- in Pages/MSUF_Menu2_GlobalBars.lua, and that page writes through BarScopeSet,
-- so the same range governs every unit and group scope the bar-scope selector
-- covers. Without this the generated fallbacks stayed read-only and a plain
-- "set target absorb bar height to 6" was refused even though the slider for it
-- is right there in the menu.
--
-- Only leaves whose binding is unambiguous belong here; a leaf bound twice with
-- different ranges must stay read-only rather than pick a winner.
-- assistant_menu_slider_domain_smoke re-reads the options source and fails if
-- any entry drifts from its binding, so this table cannot rot silently.
local REVIEWED_MENU_DOMAINS = {
    absorbBarHeight = { min = 0, max = 100, step = 1, source = "absorb.absorbBarHeight" },
    absorbBarOffsetY = { min = -100, max = 100, step = 1, source = "absorb.absorbBarOffsetY" },
    healAbsorbBarHeight = { min = 0, max = 100, step = 1, source = "absorb.healAbsorbBarHeight" },
    healAbsorbBarOffsetY = { min = -100, max = 100, step = 1, source = "absorb.healAbsorbBarOffsetY" },
    healPredictionBarHeight = { min = 0, max = 100, step = 1, source = "absorb.healPredictionBarHeight" },
    healPredictionBarOffsetY = { min = -100, max = 100, step = 1, source = "absorb.healPredictionBarOffsetY" },
    healPredictionBarOpacity = { min = 0, max = 1, step = 0.05, source = "absorb.healPredictionBarOpacity" },

    -- Labelled sliders on the same bar-scope page: bound by widget rather than
    -- by literal key, but still written through BarScopeSet, so one range again
    -- governs every scope.
    tempMaxHealthOpacity = { min = 0.05, max = 1, step = 0.05, source = "temp_max_health.opacity",
        sharedSlider = { file = "Pages/MSUF_Menu2_GlobalBars.lua", label = "Overlay opacity" } },
    tempMaxHealthBackgroundOpacity = { min = 0, max = 1, step = 0.05,
        source = "temp_max_health.background_opacity",
        sharedSlider = { file = "Pages/MSUF_Menu2_GlobalBars.lua", label = "Background opacity" } },

    -- The highlight thickness slider writes highlightBorderThickness and this
    -- legacy twin in the same setter, so both carry its range.
    hlAggroSize = { min = 1, max = 30, step = 1, source = "highlight.border_thickness",
        sharedSlider = { file = "Pages/MSUF_Menu2_GlobalBars.lua", label = "Highlight border thickness" } },

    -- Bound through a shared placement slider rather than by literal key: the
    -- status section builds one Size slider and drives whichever indicator the
    -- descriptor selects, so every status size field carries that same range.
    -- The sibling sizes (combat/pvp/rested/elite/incomingRes) already reach it
    -- through a curated entry; these two had none.
    leaderIconSize = { min = 8, max = 64, step = 1, source = "status.placement.size",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Size" } },
    raidMarkerSize = { min = 8, max = 64, step = 1, source = "status.placement.size",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Size" } },
    -- The unit text appearance slider and the group text scope slider agree on
    -- this range, so the name font size is unambiguous across both.
    nameFontSize = { min = 6, max = 48, step = 1, source = "text.appearance.size",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitText.lua", label = "Default size" } },
    -- Same shared status Size slider as the icon sizes above; the DND text is
    -- just another descriptor the placement card drives.
    -- BindGradientStrength computes its label into a variable, so the entry is
    -- pinned to that helper rather than a label literal; it builds exactly one
    -- slider, W.Slider(textures, label, 0, 1, 0.05, 220).
    powerGradientStrength = { min = 0, max = 1, step = 0.05, source = "gradient.power.strength",
        sharedSlider = { file = "Pages/MSUF_Menu2_GlobalBars.lua",
            enclosing = "BindGradientStrength" } },
    statusDNDTextSize = { min = 8, max = 64, step = 1, source = "status.placement.size",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Size" } },
    -- BindStatusPlacementSlider(card, "Layer", 0, 30, …) states no step literal;
    -- the widget rounds to whole numbers, so step 1 is the ledger's part.
    statusDNDTextLayer = { min = 0, max = 30, step = 1, source = "status.placement.layer",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Layer" } },
    -- ScopeNumberSlider(ctx, card, "Effect Layer (0-30)", 0, 30, 1, …) binds the
    -- group dispel overlay layer by literal key on the group bars page.
    dispelOverlayLayer = { min = 0, max = 30, step = 1, source = "visual.dispel.layer",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Effect Layer (0-30)" } },

    -- The Dispel Symbol card (BuildGFDispelSymbolSection) binds every number it
    -- owns through ScopeNumberSlider with a literal range, so the whole card
    -- transcribes without inference. Its layer slider reuses the same
    -- "Effect Layer (0-30)" label and the same 0..30 range as the dispel overlay
    -- above, so the shared-label lookup still resolves to one domain.
    dispelSymbolSize = { min = 4, max = 48, step = 1, source = "visual.dispel.symbol.size",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Symbol size" } },
    dispelSymbolX = { min = -128, max = 128, step = 1, source = "visual.dispel.symbol.x",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Offset X" } },
    dispelSymbolY = { min = -128, max = 128, step = 1, source = "visual.dispel.symbol.y",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Offset Y" } },
    dispelSymbolSpacing = { min = 0, max = 32, step = 1, source = "visual.dispel.symbol.spacing",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Symbol spacing" } },
    dispelSymbolAlpha = { min = 0.05, max = 1, step = 0.05, source = "visual.dispel.symbol.opacity",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Symbol opacity" } },
    dispelSymbolLayer = { min = 0, max = 30, step = 1, source = "visual.dispel.symbol.layer",
        sharedSlider = { file = "Pages/MSUF_Menu2_GroupBars.lua", label = "Effect Layer (0-30)" } },

    -- Status text placement offsets. The status section binds X/Y twice against
    -- the SAME descriptor field: the standard card at -500..500 and an extended
    -- card at -1000..1000. Both write spec.x / spec.y, so the extended pair is
    -- the widest range the shipped menu can actually produce, and transcribing
    -- it means the Assistant never refuses a placement a player can set by hand.
    -- BindStatusPlacementSlider states no step literal (it builds
    -- W.Slider(parent, label, minValue, maxValue, 1, 300) and rounds to whole
    -- numbers), so step 1 is the ledger's part, exactly as for the Layer entry.
    statusAFKTextOffsetX = { min = -1000, max = 1000, step = 1, source = "status.placement.x",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "X Offset (extended)" } },
    statusAFKTextOffsetY = { min = -1000, max = 1000, step = 1, source = "status.placement.y",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Y Offset (extended)" } },
    statusDNDTextOffsetX = { min = -1000, max = 1000, step = 1, source = "status.placement.x",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "X Offset (extended)" } },
    statusDNDTextOffsetY = { min = -1000, max = 1000, step = 1, source = "status.placement.y",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Y Offset (extended)" } },
    statusGhostTextOffsetX = { min = -1000, max = 1000, step = 1, source = "status.placement.x",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "X Offset (extended)" } },
    statusGhostTextOffsetY = { min = -1000, max = 1000, step = 1, source = "status.placement.y",
        sharedSlider = { file = "Pages/MSUF_Menu2_UnitStatusSection.lua", label = "Y Offset (extended)" } },
}
Auto.ReviewedMenuDomains = REVIEWED_MENU_DOMAINS

-- Curation pass: give a generated read-only number a safe write domain when a
-- reviewed, curated (non-generated) sibling with the SAME leaf key exists and
-- every such sibling AGREES on min, max, and percent.  Same leaf across frames
-- means the same attribute (boss.combatStateIndicatorSize inherits the
-- reviewed [8..64] of player.combatStateIndicatorSize), so the domain transfers
-- without any guessing.  Generic leaves and any leaf whose curated siblings
-- disagree are left read-only.  This only copies static metadata onto an
-- already-registered spec, so it adds no runtime events and zero combat cost.
function Auto.PromoteInheritedNumberDomains()
    local Registry = A.Registry
    if not (Registry and type(Registry.AllSettings) == "function") then return 0 end
    local settings = Registry:AllSettings()

    -- Build per-leaf domains and detect disagreement. The reviewed Menu2
    -- ranges seed the table first: an explicitly transcribed binding is
    -- evidence, not inference, so it outranks anything derived from a sibling
    -- and is never subject to the generic-leaf guard below.
    local domainByLeaf = {}
    for leaf, reviewed in pairs(REVIEWED_MENU_DOMAINS) do
        domainByLeaf[leaf] = {
            min = reviewed.min, max = reviewed.max, step = reviewed.step,
            -- A 0..1 range is a fraction the menu shows as a percentage, which
            -- is what lets "set it to 50" mean 0.5 rather than clamping to 1.
            percent = reviewed.percent == true or (reviewed.max ~= nil and reviewed.max <= 1),
            source = reviewed.source, reviewed = true, conflict = false,
        }
    end
    for i = 1, #settings do
        local s = settings[i]
        if type(s) == "table" and s.generated ~= true and s.type == "number"
            and (s.min ~= nil or s.max ~= nil)
        then
            local leaf = PromotionLeaf(s.key)
            if not UNSAFE_PROMOTION_LEAVES[leaf] then
                local entry = domainByLeaf[leaf]
                local percent = s.percent == true
                if entry == nil then
                    domainByLeaf[leaf] = {
                        min = s.min, max = s.max, step = s.step, percent = percent,
                        source = s.key, conflict = false,
                    }
                elseif entry.reviewed then
                    -- The transcribed menu binding is the control's real range.
                    -- A curated sibling that happens to disagree describes a
                    -- different control, so it neither overrides nor invalidates
                    -- the reviewed entry.
                elseif not entry.conflict then
                    if entry.min ~= s.min or entry.max ~= s.max or entry.percent ~= percent then
                        entry.conflict = true
                    end
                end
            end
        end
    end

    local promoted = 0
    for i = 1, #settings do
        local s = settings[i]
        -- A color channel is never promotable: whatever domain a curated
        -- sibling proves, one channel is still not an independently settable
        -- control, so it must keep pointing at the whole-color path.
        if type(s) == "table" and s.generated == true and s.type == "number"
            and s.assistantColorChannel ~= true
            and s.assistantMutationSafe == false and s.min == nil and s.max == nil
        then
            local domain = domainByLeaf[PromotionLeaf(s.key)]
            if domain and not domain.conflict and domain.min ~= nil and domain.max ~= nil
                and domain.min < domain.max
            then
                s.min = domain.min
                s.max = domain.max
                if domain.step ~= nil then s.step = domain.step end
                s.percent = domain.percent
                s.assistantMutationSafe = true
                s.generatedMutationSafety = domain.reviewed
                    and "reviewed-menu-domain" or "inherited-curated-domain"
                s.mutationDomainSource = domain.source
                s.unsafeMutationReason = nil
                promoted = promoted + 1
            end
        end
    end
    Auto.lastDomainPromotionCount = promoted
    return promoted
end

-- Curation pass for generated STRINGS, mirroring the number pass above.
--
-- A generated string ships read-only because an arbitrary string write can put
-- a value into the DB that the runtime never expects. A closed list of allowed
-- values removes exactly that risk, and for these fields the list already
-- exists: the same attribute is a reviewed enum on another frame, e.g. every
-- curated *.restedStateIndicatorAnchor offers the same four corners. Same leaf
-- means the same attribute, so when every curated sibling agrees on the value
-- set it transfers without any guessing; one disagreement and the field stays
-- read-only.
--
-- Only static metadata is copied onto an already-registered spec, so this adds
-- no events and no combat cost, exactly like the number pass.
-- Exact paths that share a leaf with a reviewed control but are deliberately
-- NOT the same control, so a sibling's value list must not transfer to them.
-- Recorded exactly rather than by pattern, like every other reviewed ledger
-- here; assistant_autocoverage_safety_regression pins the same decision from
-- the opposite side ("must remain a read-only generated setting").
local NON_ALIAS_PROMOTION_KEYS = {
    ["general.hpTextSeparator"] = true,
    ["general.powerTextSeparator"] = true,
}
Auto.NonAliasPromotionKeys = NON_ALIAS_PROMOTION_KEYS

-- Frame strata is a closed Blizzard enum, not an MSUF invention, and the two
-- options tables that offer it (FRAME_STRATA_CHOICES in MSUF_Menu2_LayerOverview
-- and FRAME_STRATA_VALUES in Pages/MSUF_Menu2_Group) list exactly these nine in
-- this order; only their display text differs. AUTO means "inherit from the
-- frame" and is a real choice in both, so it belongs in the list.
local FRAME_STRATA_VALUES = {
    "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH",
    "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}

-- Reviewed value lists for generated strings whose control exists in the menu
-- but has no curated registry sibling to inherit from. Same contract as
-- REVIEWED_MENU_DOMAINS: transcribed from the options source, and
-- assistant_value_list_promotion_smoke re-reads that source so an entry cannot
-- drift from the dropdown the player sees.
local REVIEWED_MENU_VALUES = {
    barOutlineStrata = { values = FRAME_STRATA_VALUES, source = "layer.frame_strata",
        sharedValues = { file = "MSUF_Menu2_LayerOverview.lua", table = "FRAME_STRATA_CHOICES" } },
    ciStrata = { values = FRAME_STRATA_VALUES, source = "layer.frame_strata",
        sharedValues = { file = "MSUF_Menu2_LayerOverview.lua", table = "FRAME_STRATA_CHOICES" } },
    dispelOverlayStrata = { values = FRAME_STRATA_VALUES, source = "layer.frame_strata",
        sharedValues = { file = "MSUF_Menu2_LayerOverview.lua", table = "FRAME_STRATA_CHOICES" } },

    -- Numeric enums: stored as numbers, chosen from a dropdown. The runtime
    -- reads them per scope with a general fallback (MSUF_UF_Config.lua:1941),
    -- so every scope is a live control. Heal-absorb deliberately omits mode 4
    -- ("Follow HP bar (overflow)"), which is why it cannot share the
    -- heal-prediction list; both are bound unambiguously.
    healAbsorbAnchorMode = { values = { 1, 2, 3, 5 }, numeric = true,
        source = "absorb.negative.anchor",
        sharedValues = { file = "Pages/MSUF_Menu2_GlobalBars.lua", table = "negativeAnchorValues" } },
    healPredAnchorMode = { values = { 1, 2, 3, 4, 5 }, numeric = true,
        source = "absorb.heal_prediction.anchor",
        sharedValues = { file = "Pages/MSUF_Menu2_GlobalBars.lua", table = "healAnchorValues" } },

    -- The status placement anchors are declared as a packed "VALUE=Label|..."
    -- string rather than a table, so the smoke parses that form instead.
    -- Off/On stored as 0/1: VT(0, "Off", 1, "On") in the highlight section.
    bossTargetOutlineMode = { values = { 0, 1 }, numeric = true,
        source = "highlight.boss_target.border",
        sharedValues = { file = "Pages/MSUF_Menu2_GlobalBars.lua", table = "borderModes", inlineVT = true } },

    -- One shared "Castbar provider" dropdown drives whichever castbar spec is
    -- selected. MSUF_Castbars_Backend.lua:87-91 normalizes to exactly this
    -- pair (it also tolerates the legacy BLIZZ/DEFAULT/SHOW spellings, which
    -- are not offered as choices).
    bossCastbarBackend = { values = { "MSUF", "BLIZZARD" }, source = "castbar.provider",
        sharedValues = { file = "Pages/MSUF_Menu2_UnitFrameVisuals.lua",
            table = "CASTBAR_BACKEND_VALUES", inlineVT = true, strings = true } },
    castbarTargetBackend = { values = { "MSUF", "BLIZZARD" }, source = "castbar.provider",
        sharedValues = { file = "Pages/MSUF_Menu2_UnitFrameVisuals.lua",
            table = "CASTBAR_BACKEND_VALUES", inlineVT = true, strings = true } },
    castbarFocusBackend = { values = { "MSUF", "BLIZZARD" }, source = "castbar.provider",
        sharedValues = { file = "Pages/MSUF_Menu2_UnitFrameVisuals.lua",
            table = "CASTBAR_BACKEND_VALUES", inlineVT = true, strings = true } },

    -- The options page keys its per-direction toggles by these four tokens
    -- (POWER_GRADIENT_DIR_KEYS), and the engine compares the stored string
    -- against exactly LEFT/UP/DOWN with RIGHT as the default
    -- (MSUF_UF_Core.lua:600-603).
    powerGradientDirection = { values = { "LEFT", "RIGHT", "UP", "DOWN" },
        source = "gradient.power.direction",
        sharedValues = { file = "Pages/MSUF_Menu2_GlobalBars.lua",
            table = "POWER_GRADIENT_DIR_KEYS", keyedTable = true } },

    statusDNDTextAnchor = {
        values = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER",
                   "TOP", "BOTTOM", "LEFT", "RIGHT" },
        source = "status.placement.anchor",
        sharedValues = { file = "Pages/MSUF_Menu2_Unit.lua", table = "STATUS_ANCHORS", packed = true } },
}
Auto.ReviewedMenuValues = REVIEWED_MENU_VALUES

-- Media fields cannot use a closed list: the installed texture set depends on
-- which media addons the player has. Curated texture settings solve this by
-- carrying `mediaType` and letting the media resolver validate the value at
-- write time (see any curated *.powerBarTexture: type "string", mediaType
-- "statusbar", no values). These generated twins are bound to the same texture
-- dropdown in the options page, so they get the same treatment rather than a
-- fabricated value list.
local REVIEWED_MENU_MEDIA = {
    healPredictionBarTexture = { mediaType = "statusbar",
        source = "absorb.heal_prediction.texture", menuKey = "healPredictionBarTexture" },
    tempMaxHealthTexture = { mediaType = "statusbar",
        source = "temp_max_health.texture", menuKey = "tempMaxHealthTexture" },
    barOutlineTexture = { mediaType = "border",
        source = "outline.texture", menuKey = "barOutlineTexture" },
    -- Not LibSharedMedia: the class portrait dropdown is filled from
    -- MSUF.PortraitMedia.GetPackOptions(), so the installed packs decide the
    -- choices. A fixed list would be wrong for the same reason it is wrong for
    -- textures; the resolver's portraitpack branch validates at write time.
    portraitClassStyle = { mediaType = "portraitpack",
        source = "portrait.class_style", menuKey = "portraitClassStyle",
        menuFile = "Pages/MSUF_Menu2_UnitFrameVisuals.lua", menuBuilder = "PortraitClassStyleValues" },
}
Auto.ReviewedMenuMedia = REVIEWED_MENU_MEDIA

--- Gives generated media strings the same resolver-backed write path curated
--- texture settings use. Static metadata only, so no runtime or combat cost.
function Auto.PromoteReviewedMediaTypes()
    local Registry = A.Registry
    if not (Registry and type(Registry.AllSettings) == "function") then return 0 end
    local settings = Registry:AllSettings()
    local promoted = 0
    for i = 1, #settings do
        local s = settings[i]
        if type(s) == "table" and s.generated == true and s.type == "string"
            and s.assistantColorChannel ~= true
            and not NON_ALIAS_PROMOTION_KEYS[tostring(s.key)]
            and s.assistantMutationSafe == false and s.mediaType == nil and s.values == nil
        then
            local reviewed = REVIEWED_MENU_MEDIA[PromotionLeaf(s.key)]
            if reviewed then
                s.mediaType = reviewed.mediaType
                s.assistantMutationSafe = true
                s.generatedMutationSafety = "reviewed-menu-media"
                s.mutationDomainSource = reviewed.source
                s.unsafeMutationReason = nil
                promoted = promoted + 1
            end
        end
    end
    Auto.lastMediaPromotionCount = promoted
    return promoted
end

function Auto.PromoteInheritedValueLists()
    local Registry = A.Registry
    if not (Registry and type(Registry.AllSettings) == "function") then return 0 end
    local settings = Registry:AllSettings()

    local function ValueSignature(values)
        local sorted = {}
        for i = 1, #values do sorted[i] = tostring(values[i]) end
        table.sort(sorted)
        return table.concat(sorted, "\1")
    end

    -- Reviewed menu lists seed the table first, exactly like the number pass:
    -- a transcribed dropdown is evidence, so it outranks anything derived from
    -- a sibling and cannot be invalidated by one.
    local listByLeaf = {}
    for leaf, reviewed in pairs(REVIEWED_MENU_VALUES) do
        listByLeaf[leaf] = {
            signature = ValueSignature(reviewed.values), values = reviewed.values,
            source = reviewed.source, reviewed = true, conflict = false,
        }
    end

    -- Build per-leaf curated value lists and detect disagreement.
    for i = 1, #settings do
        local s = settings[i]
        if type(s) == "table" and s.generated ~= true
            and type(s.values) == "table" and #s.values > 0
        then
            local leaf = PromotionLeaf(s.key)
            local signature = ValueSignature(s.values)
            local entry = listByLeaf[leaf]
            if entry == nil then
                listByLeaf[leaf] = {
                    signature = signature, values = s.values, valueLabels = s.valueLabels,
                    source = s.key, conflict = false,
                }
            elseif entry.reviewed then
                -- The transcribed dropdown is the control's real list. A
                -- curated sibling that disagrees describes a different control,
                -- so it neither overrides nor invalidates the reviewed entry.
            elseif entry.signature ~= signature then
                entry.conflict = true
            end
        end
    end

    local promoted = 0
    for i = 1, #settings do
        local s = settings[i]
        -- Strings inherit from any agreeing curated sibling. Numbers only ever
        -- take an explicitly reviewed list: a numeric field is a value domain
        -- by default, and turning one into a closed set on a sibling's word
        -- would silently forbid values the control still accepts.
        local leaf = type(s) == "table" and PromotionLeaf(s.key) or ""
        local reviewedNumeric = REVIEWED_MENU_VALUES[leaf] ~= nil
        if type(s) == "table" and s.generated == true
            and (s.type == "string" or (s.type == "number" and reviewedNumeric))
            and s.assistantColorChannel ~= true
            and not NON_ALIAS_PROMOTION_KEYS[tostring(s.key)]
            and s.assistantMutationSafe == false and s.values == nil
        then
            local list = listByLeaf[PromotionLeaf(s.key)]
            if list and not list.conflict and type(list.values) == "table" and #list.values > 0 then
                local values = {}
                for j = 1, #list.values do values[j] = list.values[j] end
                s.values = values
                if type(list.valueLabels) == "table" then
                    local labels = {}
                    for key, label in pairs(list.valueLabels) do labels[key] = label end
                    s.valueLabels = labels
                end
                -- A closed list is what makes the write safe, and it is what
                -- every curated enum looks like.
                s.type = "enum"
                s.closedValues = true
                s.assistantMutationSafe = true
                s.generatedMutationSafety = list.reviewed
                    and "reviewed-menu-values" or "inherited-curated-values"
                s.mutationDomainSource = list.source
                s.unsafeMutationReason = nil
                promoted = promoted + 1
            end
        end
    end
    Auto.lastValueListPromotionCount = promoted
    return promoted
end

--- Avoid building generated aliases for players who never use the assistant.
--- Failed early attempts are not latched, so a caller can retry after the
--- registry/audit modules become available.
function Auto.EnsureFilled()
    if Auto._fillComplete == true then return 0 end
    return Auto.Fill()
end
