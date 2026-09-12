--- GroupFrames/MSUF_GroupFrames_DB_Migrations.lua - cold Group Frame profile repair
--- One-time migrations, the legacy (pre-Auras3) aura model fillers, the Menu2
--- dropdown-domain repair and the ordered EnsureDB repair pipeline.
--- Loads directly after MSUF_GroupFrames_DB.lua. Nothing here runs per frame
--- or per event: GF.EnsureDB (DB.lua) keeps the stable-cache fast path and
--- calls GF.RepairGroupDB once per DB invalidation.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local GF = MSUF.GF or {}
MSUF.GF = GF
local ExportPublic = MSUF.ExportPublic

local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs

--- The defaults tables are built once by MSUF_GroupFrames_DB.lua and never
--- replaced, so capturing them at load time is equivalent to reading GF.*.
--- That equivalence only holds while this file loads after DB.lua, so state
--- the load-order contract loudly here. A manifest reorder in
--- UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Group.xml would otherwise alias
--- nil and silently disable every migration below.
if type(GF.PARTY_DEFAULTS) ~= "table"
    or type(GF.RAID_DEFAULTS) ~= "table"
    or type(GF.MYTHIC_RAID_DEFAULTS) ~= "table"
    or type(GF.PRIORITY_DEFAULTS) ~= "table"
    or type(GF.ResolveLegacyHealPredictionEnabled) ~= "function" then
    error("MSUF_GroupFrames_DB_Migrations.lua loaded before MSUF_GroupFrames_DB.lua.", 2)
end

local PARTY_DEFAULTS = GF.PARTY_DEFAULTS
local RAID_DEFAULTS = GF.RAID_DEFAULTS
local MYTHIC_RAID_DEFAULTS = GF.MYTHIC_RAID_DEFAULTS
local PRIORITY_DEFAULTS = GF.PRIORITY_DEFAULTS
local ResolveLegacyHealPredictionEnabled = GF.ResolveLegacyHealPredictionEnabled

---
--- Migration: showHP boolean - 3-slot text
---
local function MigrateShowHPTo3Slot(conf)
    if not conf then return end
    --- Only migrate if old showHP exists and no 3-slot keys set yet
    if conf.showHP ~= nil and conf.textCenter == nil and conf.textLeft == nil and conf.textRight == nil then
        if conf.showHP then
            conf.textCenter = "PERCENT"
        else
            conf.textCenter = "NONE"
        end
        conf.textLeft  = "NONE"
        conf.textRight = "NONE"
    end
    --- Remove legacy key after migration
    conf.showHP = nil
end

---
--- Migration: GF-local highlight keys - unified hl* with hlOverride
---
local HIGHLIGHT_MIGRATION_KEYS = {
    aggroHighlightSize    = "hlAggroSize",
    aggroHighlightOffset  = "hlAggroOffset",
    aggroHighlightLayer   = "hlAggroLayer",
    targetBorderSize      = "hlTargetSize",
    targetHighlightOffset = "hlTargetOffset",
    targetHighlightLayer  = "hlTargetLayer",
    hoverHighlightSize    = "hlHoverSize",
    hoverHighlightOffset  = "hlHoverOffset",
}

local function MigrateHighlightToUnified(conf)
    if not conf then return end
    if conf._hlMigrated then return end
    --- Migrate old GF-local geometry keys to hlOverride scope
    local hadCustom = false
    for oldKey, newKey in pairs(HIGHLIGHT_MIGRATION_KEYS) do
        if conf[oldKey] ~= nil then
            conf[newKey] = conf[oldKey]
            hadCustom = true
        end
    end
    if hadCustom then conf.hlOverride = true end
    conf._hlMigrated = true
end

--- Corner Indicators: migrate dropped categories ("boss", "missing") - "none".
--- These categories no longer work in 12.0 due to secret-tagged isRaid/spellId
--- on debuffs/buffs cast by other players. Replaced with "aggro" + "custom".
--- One-shot migration (idempotent via _ciMigratedV2 stamp).
local CI_DROPPED_CATEGORIES = { boss = true, missing = true }
local CI_CUSTOM_KEYS = { "ciCustomTL", "ciCustomTR", "ciCustomBL", "ciCustomBR", "ciCustomC" }
local CI_SLOT_KEYS = { "ciSlotTL", "ciSlotTR", "ciSlotBL", "ciSlotBR", "ciSlotC" }

--- Always-run defensive sweep: ensure ciCustom* slots are either a table or nil.
--- A previous build may have stamped a non-table value (e.g. number, string)
--- into one of these keys; the new option UI indexes them as tables and would
--- crash on a number/string. Cheap to run every login.
local function CleanupCornerCustomTypes(conf)
    if not conf then return end
    for _, k in ipairs(CI_CUSTOM_KEYS) do
        local v = conf[k]
        if v ~= nil and type(v) ~= "table" then conf[k] = nil end
    end
end

local function MigrateCornerIndicators(conf)
    if not conf then return end
    if conf._ciMigratedV2 then return end
    for _, k in ipairs(CI_SLOT_KEYS) do
        if CI_DROPPED_CATEGORIES[conf[k]] then conf[k] = "none" end
    end
    --- Drop legacy boss color keys (replaced by aggro color in CI v2 schema)
    conf.ciBossColorR = nil
    conf.ciBossColorG = nil
    conf.ciBossColorB = nil
    conf.ciMissingColorR = nil
    conf.ciMissingColorG = nil
    conf.ciMissingColorB = nil
    conf._ciMigratedV2 = true
end

local function RemoveGroupPetFrameConfig(conf)
    if type(conf) ~= "table" then return end
    conf.showPets = nil
    if conf.anchorToFrame == "pet" then
        conf.anchorToFrame = nil
    end
end

local function RemoveLayoutPresetState(conf)
    if type(conf) ~= "table" then return end
    conf.layoutIntentPreset = nil
end

local function NormalizeHealPredictionAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback or 3
    if mode < 1 or mode > 5 then mode = fallback or 3 end
    return mode
end

local function ResolveSharedHealPredictionAnchorMode(db)
    local gen = db.general
    return NormalizeHealPredictionAnchorMode(gen and gen.healPredAnchorMode, 3)
end

local function MigrateHealPredictionOwnership(conf, scope, db)
    if type(conf) ~= "table" then return end
    if conf.healPredEnabled == nil and conf.healPrediction ~= nil then
        conf.healPredEnabled = conf.healPrediction == true
    end
    if conf.healPredEnabled == nil then
        conf.healPredEnabled = ResolveLegacyHealPredictionEnabled(db)
    end
    conf.healPredAnchorMode = NormalizeHealPredictionAnchorMode(conf.healPredAnchorMode, 3)
    if conf._healPredBarsScopeMigrated ~= true then
        local sharedEnabled = ResolveLegacyHealPredictionEnabled(db)
        local localEnabled = conf.healPredEnabled == true
        local sharedAnchor = ResolveSharedHealPredictionAnchorMode(db)
        local localAnchor = NormalizeHealPredictionAnchorMode(conf.healPredAnchorMode, 3)
        if localEnabled ~= sharedEnabled or (localEnabled and localAnchor ~= sharedAnchor) then
            conf.hlOverride = true
        end
        conf._healPredBarsScopeMigrated = true
    end
    conf.healPrediction = nil
end

local function MigrateTextureOverrideOwnership(conf)
    if type(conf) ~= "table" or conf._barTextureOverrideMigrated == true then return end
    if (type(conf.barTexture) == "string" and conf.barTexture ~= "")
        or (type(conf.barBackgroundTexture) == "string" and conf.barBackgroundTexture ~= "")
        or (type(conf.barBgTexture) == "string" and conf.barBgTexture ~= "") then
        conf.hlOverride = true
    end
    conf._barTextureOverrideMigrated = true
end

---
--- DB init
---
local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
end

local function NormalizeFontField(conf)
    if type(conf) ~= "table" then return end
    conf.fontKey = nil
    conf.nameShortenOverride = nil
    conf._msufGFNameTruncationOverride = nil
end

local GF_NATIVE_AURA_RENDERER = "NATIVE_12_1"
local GF_CUSTOM_AURA_RENDERER = "CUSTOM"
local GF_AURA_PROFILE_MODEL_REVISION = 1
local GF_RETIRED_AURA_ROOT_KEYS = {
    "aurasEnabled", "auraMaxIcons", "auraIconSize", "auraAnchor",
    "auraGrowthX", "auraGrowthY", "auraSpacing", "auraPerRow",
    "privateAurasEnabled", "privateAuraMax", "privateAuraSize",
    "privateAuraAnchor", "privateAuraX", "privateAuraY", "privateAuraCountdown",
}
local function ClearRetiredAuraRootFields(conf)
    if type(conf) ~= "table" then return false end
    local changed = false
    for i = 1, #GF_RETIRED_AURA_ROOT_KEYS do
        local key = GF_RETIRED_AURA_ROOT_KEYS[i]
        if conf[key] ~= nil then
            conf[key] = nil
            changed = true
        end
    end
    if conf._auraMigV2 ~= nil then
        conf._auraMigV2 = nil
        changed = true
    end
    return changed
end
local GF_BLIZZARD_AURA_TYPE_DEFAULTS = {
    buffs = true,
    debuffs = true,
    dispels = true,
    externals = true,
}
local GF_AURA_GROUP_KEYS = { "buff", "debuff", "externals" }

local function NormalizeAuraRenderer(conf)
    if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
    local auras = conf.auras
    if auras.renderer ~= GF_CUSTOM_AURA_RENDERER and auras.renderer ~= GF_NATIVE_AURA_RENDERER then
        auras.renderer = GF_NATIVE_AURA_RENDERER
    end
    if auras.renderer == GF_NATIVE_AURA_RENDERER then
        if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
        for key, value in pairs(GF_BLIZZARD_AURA_TYPE_DEFAULTS) do
            if auras.blizzardTypes[key] == nil then
                auras.blizzardTypes[key] = value
            end
        end
        if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
        if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
        if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
        if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
        if auras.blizzardDispelBorder == nil then auras.blizzardDispelBorder = false end
        if auras.blizzardContainerAnchor == nil then auras.blizzardContainerAnchor = "FRAME" end
        if auras.blizzardContainerX == nil then auras.blizzardContainerX = 0 end
        if auras.blizzardContainerY == nil then auras.blizzardContainerY = 0 end
    end
end

--- Ensure spell filter fields exist on each aura sub-group.
local function RepairAuraFilters(conf)
    --- Migrate: remove legacy absorb/heal defaults that blocked global override
    if conf.absorbEnabled == true and not conf._absorbMigrated then
        conf.absorbEnabled = nil
        conf._absorbMigrated = true
    end
    if conf.healAbsorbEnabled == true and not conf._absorbMigrated then
        conf.healAbsorbEnabled = nil
    end
    --- Remove absorb keys that shadow general when hlOverride is off
    if not conf.hlOverride then
        conf.absorbEnabled = nil
        conf.absorbTextMode = nil
        conf.enableAbsorbBar = nil
    end
    if type(conf.auras) == "table" then
        for _, gk in ipairs(GF_AURA_GROUP_KEYS) do
            local g = conf.auras[gk]
            if type(g) == "table" then
                --- Migrate v3: old spellFilter/spellList - new filterToken/blacklistCats
                if not g._filterMigV3 then
                    g._filterMigV3 = true
                    --- Convert old filterMode - new filterToken
                    if g.filterMode and not g.filterToken then
                        local fm = g.filterMode
                        if fm == "RAID_PLAYER" or fm == "RAID_IN_COMBAT" or fm == "ALL_PLAYER" then
                            g.filterToken = "ALL"
                        elseif fm == "ALL" or fm == "PLAYER" or fm == "RAID" then
                            g.filterToken = fm
                        elseif fm == "NOT_PLAYER" then
                            g.filterToken = "ALL"
                        end
                    end
                    --- Convert old spellFilter+spellList - blacklistCats
                    if g.spellFilter == "BLACKLIST" and type(g.spellList) == "table" then
                        if type(g.blacklist) ~= "table" then g.blacklist = {} end
                        if type(g.blacklist.spells) ~= "table" then g.blacklist.spells = {} end
                        for spellID, enabled in pairs(g.spellList) do
                            if enabled == true then
                                local id = tonumber(spellID)
                                if id then g.blacklist.spells[tostring(math.floor(id + 0.5))] = true end
                            end
                        end
                        if not g.blacklistCats then g.blacklistCats = {} end
                        --- Check if old spellList contained Sated spells
                        if g.spellList[57723] or g.spellList[57724] or g.spellList[80354] then
                            g.blacklistCats.SATED = true
                        end
                        if g.spellList[26013] or g.spellList[71041] then
                            g.blacklistCats.DESERTER = true
                        end
                    end
                    --- Clean up legacy keys
                    g.spellFilter = nil
                    g.spellList   = nil
                    g.filterMode  = nil
                end
                --- Ensure new keys exist with defaults
                if g.filterToken == nil then
                    g.filterToken = (gk == "externals") and "RAID" or "ALL"
                end
                --- This runs only during the cold EnsureDB repair pass.
                --- Retired/unknown native filters must not remain active
                --- invisibly after their controls were removed from Menu2.
                if gk == "buff" or gk == "debuff" then
                    local AF = GF.AuraFilter or _G.MSUF_GF_AuraFilter
                    local normalize = AF and AF.NormalizeFilterToken
                    if type(normalize) == "function" then
                        g.filterToken = normalize(gk, g.filterToken)
                    end
                end
                if type(g.blacklistCats) ~= "table" then
                    --- Apply sensible defaults from AuraFilter module
                    local AF = GF.AuraFilter or _G.MSUF_GF_AuraFilter
                    if AF then
                        local defs = (gk == "buff") and AF.DEFAULT_BLACKLIST_BUFF
                                  or (gk == "debuff") and AF.DEFAULT_BLACKLIST_DEBUFF
                                  or nil
                        if defs then
                            g.blacklistCats = {}
                            for k, v in pairs(defs) do g.blacklistCats[k] = v end
                        else
                            g.blacklistCats = {}
                        end
                    else
                        g.blacklistCats = {}
                    end
                end
                if type(g.blacklist) ~= "table" then g.blacklist = {} end
                if type(g.blacklist.spells) ~= "table" then g.blacklist.spells = {} end
                if g.showDurationBar == nil then g.showDurationBar = false end
                if g.durationBarHeight == nil then g.durationBarHeight = 2 end
                if g.durationBarDisplay ~= "OVERLAY" then g.durationBarDisplay = "BAR_ONLY" end
                if g.durationBarPosition ~= "TOP" then g.durationBarPosition = "BOTTOM" end
                if g.durationBarDirection ~= "ELAPSED" then g.durationBarDirection = "REMAINING" end
            end
        end
    end
end

--- Migration v2: force-enable auras + defensives (showstopper fix)
local function RepairAuraV2(conf)
    if type(conf.auras) == "table"
        and tonumber(conf.auras.profileModelRevision) ~= GF_AURA_PROFILE_MODEL_REVISION
        and not conf._auraMigV2 then
        conf._auraMigV2 = true
        if conf.auras.enabled == false or conf.auras.enabled == nil then
            conf.auras.enabled = true
        end
        local ext = conf.auras.externals
        if type(ext) == "table" and not ext.enabled then
            ext.enabled = true
        end
    end
end

local function MigrateSplitDNDStatusText(conf)
    if type(conf) ~= "table" or conf.statusDNDText ~= nil or conf.statusAFKText == nil then return end
    conf.statusDNDText = conf.statusAFKText
    conf.statusDNDTextSize = conf.statusAFKTextSize
    conf.statusDNDTextAnchor = conf.statusAFKTextAnchor
    conf.statusDNDTextLayer = conf.statusAFKTextLayer
    conf.statusDNDOffsetX = conf.statusAFKOffsetX
    conf.statusDNDOffsetY = conf.statusAFKOffsetY
end

-- RC1-RC8 briefly exported the Group page's option tables through one
-- positional key list. One missing key shifted every following dropdown onto
-- the next domain. Keep repair here, at the existing cold DB boundary, so bad
-- selections from those builds cannot leak into runtime specs or reappear
-- after a profile import. Stable EnsureDB calls still return before any scan.
local GROUP_MENU_DOMAIN_REPAIR = {
    revision = 1,
    nameAnchors = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
    },
    framePoints = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    },
    sortModes = { INDEX = true, NAME = true, ROLE = true, GROUP = true, GROUP_ROLE = true },
    powerTextModes = {
        NONE = true, PERCENT = true, CURRENT = true, FULLVALUE = true, MAX = true, DEFICIT = true,
        CURMAX = true, CURPERCENT = true, CURMAXPERCENT = true, MAXPERCENT = true,
        PERCENTCUR = true, PERCENTMAX = true, PERCENTCURMAX = true,
    },
    dispelOverlayStyles = { FULL = true, BOTTOM = true, TOP = true, LEFT = true, RIGHT = true },
    debuffStripeEdges = { BOTTOM = true, TOP = true },
    placedIndicatorTypes = { icon = true, square = true, bar = true, number = true },
    frameEffectTypes = { healthtint = true, border = true, glow = true, pulse = true, namecolor = true },
    -- Timed full-frame effects cannot be driven reliably from secret 12.1
    -- group auras. Retained profile values fall back to the active-aura path.
    frameEffectTimings = { always = true },
    iconEffectTypes = { none = true, glow = true },
    spellGrowth = { RIGHTDOWN = true, LEFTDOWN = true, RIGHTUP = true, LEFTUP = true },
    shiftedNameAnchors = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true },
    shiftedAnchorTargets = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    },
    shiftedDelimiters = { LEFT = true, CENTER = true, RIGHT = true },
    statusAnchorFields = {
        "roleIconAnchor", "leaderIconAnchor", "assistIconAnchor", "raidMarkerAnchor",
        "readyCheckAnchor", "summonAnchor", "resurrectAnchor", "pvpIconAnchor", "phaseAnchor",
        "statusTextAnchor", "statusGhostTextAnchor", "statusAFKTextAnchor", "statusAFKTimerTextAnchor", "statusDNDTextAnchor",
        "groupNumberAnchor", "dispelSymbolAnchor",
    },
    auraDefaults = {
        buff = { anchor = "BOTTOMRIGHT", cooldownAnchor = "CENTER", stackAnchor = "BOTTOMRIGHT" },
        debuff = { anchor = "TOPLEFT", cooldownAnchor = "CENTER", stackAnchor = "BOTTOMRIGHT" },
        externals = { anchor = "CENTER", cooldownAnchor = "CENTER", stackAnchor = "BOTTOMRIGHT" },
    },
}

function GROUP_MENU_DOMAIN_REPAIR.EnumField(owner, key, allowed, fallback)
    local value = owner and owner[key]
    if value ~= nil and not allowed[value] then owner[key] = fallback end
end

function GROUP_MENU_DOMAIN_REPAIR.SpellIndicators(conf)
    local si = conf and conf.spellIndicators
    local specs = type(si) == "table" and si.specs or nil
    if type(specs) ~= "table" then return end
    for _, spec in pairs(specs) do
        if type(spec) == "table" then
            for _, entry in pairs(spec) do
                if type(entry) == "table" then
                    local placed = entry.placed
                    if type(placed) == "table" then
                        if not GROUP_MENU_DOMAIN_REPAIR.placedIndicatorTypes[placed.type] then
                            entry.placed = false
                        else
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(placed, "anchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, "TOPLEFT")
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(placed, "growth", GROUP_MENU_DOMAIN_REPAIR.spellGrowth, "RIGHTDOWN")
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(placed, "iconEffect", GROUP_MENU_DOMAIN_REPAIR.iconEffectTypes, "none")
                        end
                    end
                    local frame = entry.frame
                    if type(frame) == "table" then
                        if not GROUP_MENU_DOMAIN_REPAIR.frameEffectTypes[frame.type] then
                            entry.frame = false
                        else
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(frame, "timing", GROUP_MENU_DOMAIN_REPAIR.frameEffectTimings, "always")
                        end
                    end
                end
            end
        end
    end
end

function GROUP_MENU_DOMAIN_REPAIR.Conf(conf, defaults, isRaid)
    if type(conf) ~= "table" then return end
    defaults = defaults or PARTY_DEFAULTS

    -- TOP*/BOTTOM* were the four aura-corner choices accidentally shown for
    -- Name. Before the fix every one rendered through the LEFT fallback, so a
    -- one-time reset to LEFT preserves the user's actual on-screen geometry.
    if conf._menuSpecDomainRepair ~= GROUP_MENU_DOMAIN_REPAIR.revision then
        if GROUP_MENU_DOMAIN_REPAIR.shiftedNameAnchors[conf.nameAnchor] then conf.nameAnchor = defaults.nameAnchor or "LEFT" end
        if GROUP_MENU_DOMAIN_REPAIR.shiftedAnchorTargets[conf.anchorToFrame] then conf.anchorToFrame = nil end
        conf._menuSpecDomainRepair = GROUP_MENU_DOMAIN_REPAIR.revision
    end

    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "nameAnchor", GROUP_MENU_DOMAIN_REPAIR.nameAnchors, defaults.nameAnchor or "LEFT")
    if not GROUP_MENU_DOMAIN_REPAIR.sortModes[conf.sortMode] then
        if isRaid == true and conf.preserveRaidGroups == true then
            conf.sortMode = "GROUP"
        elseif conf.sortByRole == true then
            conf.sortMode = "ROLE"
        elseif conf.sortByName == true then
            conf.sortMode = "NAME"
        else
            conf.sortMode = "INDEX"
        end
    end
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "powerTextLeft", GROUP_MENU_DOMAIN_REPAIR.powerTextModes, defaults.powerTextLeft or "NONE")
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "powerTextCenter", GROUP_MENU_DOMAIN_REPAIR.powerTextModes, defaults.powerTextCenter or "PERCENT")
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "powerTextRight", GROUP_MENU_DOMAIN_REPAIR.powerTextModes, defaults.powerTextRight or "NONE")
    if GROUP_MENU_DOMAIN_REPAIR.shiftedDelimiters[conf.textDelimiter] then conf.textDelimiter = defaults.textDelimiter or " / " end
    if GROUP_MENU_DOMAIN_REPAIR.shiftedDelimiters[conf.powerTextDelimiter] then conf.powerTextDelimiter = defaults.powerTextDelimiter or " / " end
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "dispelOverlayStyle", GROUP_MENU_DOMAIN_REPAIR.dispelOverlayStyles, defaults.dispelOverlayStyle or "FULL")
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "debuffStripeEdge", GROUP_MENU_DOMAIN_REPAIR.debuffStripeEdges, defaults.debuffStripeEdge or "BOTTOM")

    for i = 1, #GROUP_MENU_DOMAIN_REPAIR.statusAnchorFields do
        local key = GROUP_MENU_DOMAIN_REPAIR.statusAnchorFields[i]
        GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, key, GROUP_MENU_DOMAIN_REPAIR.framePoints, defaults[key] or "CENTER")
    end
    local auras = conf.auras
    if type(auras) == "table" then
        for lane, laneDefaults in pairs(GROUP_MENU_DOMAIN_REPAIR.auraDefaults) do
            local group = auras[lane]
            if type(group) == "table" then
                GROUP_MENU_DOMAIN_REPAIR.EnumField(group, "anchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, laneDefaults.anchor)
                GROUP_MENU_DOMAIN_REPAIR.EnumField(group, "cooldownAnchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, laneDefaults.cooldownAnchor)
                GROUP_MENU_DOMAIN_REPAIR.EnumField(group, "stackAnchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, laneDefaults.stackAnchor)
            end
        end
    end
    GROUP_MENU_DOMAIN_REPAIR.SpellIndicators(conf)
end

local function MigratePortraitSizeMode(conf)
    if type(conf) ~= "table" then return end
    if conf.portraitSizeMode == "UNIFORM" or conf.portraitSizeMode == "SEPARATE" then return end
    -- Party's legacy compiler let either positive axis win even when the
    -- uniform Size field was also populated. Preserve that visible geometry.
    if (tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0 then
        conf.portraitSizeMode = "SEPARATE"
    else
        conf.portraitSizeMode = "UNIFORM"
    end
end

--- MSUF <= 5.57 stored early Group Frame aura settings as flat fields. The
--- 5.57 runtime migrated them through GF.MigrateAuraConfig, but that owner no
--- longer exists in 6.0. Keep the migration in the DB layer so it runs for
--- SavedVariables startup, profile switches, full imports, and group-only
--- snapshot imports before the compiled Group Frame spec consumes the data.
local function LegacyAuraGrowth(conf, fallback)
    local x = tostring(conf and conf.auraGrowthX or ""):upper()
    local y = tostring(conf and conf.auraGrowthY or ""):upper()
    if x == "UP" or x == "DOWN" then return x end
    if x ~= "LEFT" and x ~= "RIGHT" then return fallback end
    if y ~= "UP" and y ~= "DOWN" then return x .. (fallback:find("UP", 1, true) and "UP" or "DOWN") end
    return x .. y
end

local LEGACY_BUFF_DEFAULTS = {
    enabled = true, anchor = "BOTTOMRIGHT", growth = "LEFTUP",
    x = 0, y = 0, size = 22, iconScale = 100, iconZoom = 100, iconShape = "RECTANGLE", perRow = 4, max = 6, spacing = 1,
    layer = 5, filterMode = "RAID_PLAYER",
    showCooldownSwipe = true, showCooldown = true, cooldownAnchor = "CENTER",
    cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
    showStacks = true, stackAnchor = "BOTTOMRIGHT",
    stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
}

local LEGACY_DEBUFF_DEFAULTS = {
    enabled = true, anchor = "TOPLEFT", growth = "RIGHTDOWN",
    x = 0, y = 0, size = 20, iconScale = 100, iconZoom = 100, iconShape = "RECTANGLE", perRow = 3, max = 6, spacing = 1,
    layer = 6, showDispelBorder = true,
    showCooldownSwipe = true, showCooldown = true, cooldownAnchor = "CENTER",
    cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
    showStacks = true, stackAnchor = "BOTTOMRIGHT",
    stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
}

local LEGACY_EXTERNAL_DEFAULTS = {
    enabled = true, anchor = "CENTER", growth = "RIGHTDOWN",
    x = 0, y = 0, size = 28, iconScale = 100, iconZoom = 100, iconShape = "RECTANGLE", perRow = 3, max = 2, spacing = 1,
    layer = 7, autoBlacklistBuffs = true,
    showCooldownSwipe = true, showCooldown = true, cooldownAnchor = "CENTER",
    cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 10, cooldownOutline = "OUTLINE",
    showStacks = false, stackAnchor = "BOTTOMRIGHT",
    stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
}

local function CopyAuraDefaults(defaults)
    local copy = {}
    for key, value in pairs(defaults) do copy[key] = value end
    return copy
end

local function FillMissingAuraModel(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for key, value in pairs(src) do
        if dst[key] == nil then
            if type(value) == "table" then
                local copy = {}
                FillMissingAuraModel(copy, value)
                dst[key] = copy
            else
                dst[key] = value
            end
            changed = true
        elseif type(dst[key]) == "table" and type(value) == "table" then
            changed = FillMissingAuraModel(dst[key], value) or changed
        end
    end
    return changed
end

local function LegacyBuffDefaults()
    return CopyAuraDefaults(LEGACY_BUFF_DEFAULTS)
end

local function LegacyDebuffDefaults()
    return CopyAuraDefaults(LEGACY_DEBUFF_DEFAULTS)
end

local function LegacyExternalDefaults()
    return CopyAuraDefaults(LEGACY_EXTERNAL_DEFAULTS)
end

local function LegacyPrivateAuraDefaults()
    return {
        enabled = true, max = 4, size = 20, anchor = "TOPRIGHT",
        direction = "LEFT", spacing = 1, x = 0, y = 0, layer = 8,
        showCountdown = true, showNumbers = false,
        showDispelType = false, showDuration = false,
        durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -1,
    }
end

local function FillMissingAuraFields(group, defaults)
    if type(group) ~= "table" then return end
    for key, value in pairs(defaults) do
        if group[key] == nil then group[key] = value end
    end
end

local function SpellIndicatorStyleDefaults(conf)
    local auras = type(conf) == "table" and conf.auras or nil
    local buff = type(auras) == "table" and type(auras.buff) == "table" and auras.buff or LEGACY_BUFF_DEFAULTS
    local rootTooltip = type(auras) == "table" and auras.showTooltip
    local showTooltip
    if buff.showTooltip ~= nil then
        showTooltip = buff.showTooltip ~= false
    else
        showTooltip = rootTooltip ~= false
    end
    return {
        alpha = tonumber(buff.alpha) or 1,
        showTooltip = showTooltip,
        showCooldownText = buff.showCooldown ~= false,
        showCooldownSwipe = buff.showCooldownSwipe ~= false,
        cooldownSwipeReverse = buff.cooldownSwipeReverse == true,
        cooldownSize = tonumber(buff.cooldownSize) or 8,
        cooldownAnchor = buff.cooldownAnchor or "CENTER",
        cooldownX = tonumber(buff.cooldownX or buff.cooldownOffsetX) or 0,
        cooldownY = tonumber(buff.cooldownY or buff.cooldownOffsetY) or 0,
        cooldownDecimalSeconds = tonumber(buff.cooldownDecimalSeconds) or 3,
        showDurationBar = buff.showDurationBar == true,
        durationBarHeight = tonumber(buff.durationBarHeight) or 2,
        durationBarDisplay = buff.durationBarDisplay or "BAR_ONLY",
        durationBarPosition = buff.durationBarPosition or "BOTTOM",
        durationBarDirection = buff.durationBarDirection or "REMAINING",
        showStacks = buff.showStacks ~= false,
        stackSize = tonumber(buff.stackSize) or 10,
        stackAnchor = buff.stackAnchor or "BOTTOMRIGHT",
        stackX = tonumber(buff.stackX or buff.stackOffsetX) or 0,
        stackY = tonumber(buff.stackY or buff.stackOffsetY) or 0,
    }
end

--- Ensures the per-scope Spell Icon deep-Style block exists. Shape, border and
--- shadow always come from shared Buff Appearance and are intentionally absent.
function GF.EnsureSpellIndicatorStyle(conf)
    if type(conf) ~= "table" then return nil, false end
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, iconZoom = 100, iconScale = 100 }
    end
    local si = conf.spellIndicators
    local defaults = SpellIndicatorStyleDefaults(conf)
    local changed = false
    if type(si.style) ~= "table" then
        si.style = defaults
        changed = true
    else
        if si.style.iconShape ~= nil then
            si.style.iconShape = nil
            changed = true
        end
        for key, value in pairs(defaults) do
            if si.style[key] == nil then
                si.style[key] = value
                changed = true
            end
        end
    end
    return si.style, changed
end

function GF.MigrateAuraConfig(conf, isRaid)
    if type(conf) ~= "table" then return false end
    local changed = false
    if type(conf.auras) == "table"
        and tonumber(conf.auras.profileModelRevision) == GF_AURA_PROFILE_MODEL_REVISION then
        -- applyDefaults still carries the pre-Auras3 compatibility keys for
        -- genuinely legacy profiles. Never let those aliases become persisted
        -- state again once the canonical native model owns this scope.
        changed = ClearRetiredAuraRootFields(conf) or changed
        -- Native 6.0 profiles are completed only from the native factory
        -- model. Never run the legacy flat/Aura2 default fillers over them.
        local createCanonical = (type(MSUF) == "table" and MSUF.MSUF_CreateCanonicalGroupAuraState)
            or _G.MSUF_CreateCanonicalGroupAuraState
        if type(createCanonical) == "function" then
            -- This is repair of an existing canonical profile, not a factory
            -- creation/reset. Fill missing fields with the former filter
            -- defaults so installing a new built-in filter cannot opt it in.
            local state = createCanonical(true)
            state = type(state) == "table" and state[isRaid and "gf_raid" or "gf_party"] or nil
            if type(state) == "table" then
                changed = FillMissingAuraModel(conf.auras, state.auras) or changed
                if type(conf.privateAuras) ~= "table" and type(state.privateAuras) == "table" then
                    conf.privateAuras = {}
                    FillMissingAuraModel(conf.privateAuras, state.privateAuras)
                    changed = true
                end
                if type(conf.spellIndicators) ~= "table" and type(state.spellIndicators) == "table" then
                    conf.spellIndicators = {}
                    FillMissingAuraModel(conf.spellIndicators, state.spellIndicators)
                    changed = true
                end
            end
        end
        if type(GF.EnsureSpellIndicatorStyle) == "function" then
            local _, styleChanged = GF.EnsureSpellIndicatorStyle(conf)
            changed = styleChanged or changed
        end
        return changed
    end
    local hadFlatAuras = conf.aurasEnabled ~= nil and type(conf.auras) ~= "table"
    if hadFlatAuras then
        local buff = LegacyBuffDefaults()
        local debuff = LegacyDebuffDefaults()
        local enabled = conf.aurasEnabled ~= false
        local iconSize = tonumber(conf.auraIconSize) or 20
        local maxIcons = tonumber(conf.auraMaxIcons) or 4
        local perRow = tonumber(conf.auraPerRow) or maxIcons
        local spacing = tonumber(conf.auraSpacing) or 1
        buff.enabled = enabled
        buff.anchor = conf.auraAnchor or "BOTTOMLEFT"
        buff.growth = LegacyAuraGrowth(conf, buff.growth)
        buff.size, buff.max, buff.perRow, buff.spacing = iconSize, maxIcons, perRow, spacing
        debuff.size, debuff.max, debuff.spacing = iconSize, maxIcons, spacing
        conf.auras = {
            enabled = enabled,
            buff = buff,
            debuff = debuff,
            externals = LegacyExternalDefaults(),
        }
        -- This was an explicit user setting, not the old broken default that
        -- _auraMigV2 was designed to force on. Preserve an intentional false.
        conf._auraMigV2 = true
        conf.aurasEnabled = nil
        conf.auraMaxIcons = nil
        conf.auraIconSize = nil
        conf.auraAnchor = nil
        conf.auraGrowthX = nil
        conf.auraGrowthY = nil
        conf.auraSpacing = nil
        conf.auraPerRow = nil
        changed = true
    end
    if type(conf.auras) ~= "table" then
        local buff, debuff, externals = LegacyBuffDefaults(), LegacyDebuffDefaults(), LegacyExternalDefaults()
        if isRaid == true then
            buff.size, buff.max, buff.perRow = 16, 3, 3
            debuff.size, debuff.max, debuff.perRow = 14, 3, 3
            externals.size, externals.max, externals.perRow = 24, 2, 2
        end
        conf.auras = { enabled = true, buff = buff, debuff = debuff, externals = externals }
        changed = true
    end
    if conf.privateAurasEnabled ~= nil and type(conf.privateAuras) ~= "table" then
        local private = LegacyPrivateAuraDefaults()
        private.enabled = conf.privateAurasEnabled ~= false
        private.max = tonumber(conf.privateAuraMax) or 4
        private.size = tonumber(conf.privateAuraSize) or 20
        private.anchor = conf.privateAuraAnchor or "TOPRIGHT"
        private.x = tonumber(conf.privateAuraX) or 0
        private.y = tonumber(conf.privateAuraY) or 0
        private.showCountdown = conf.privateAuraCountdown ~= false
        conf.privateAuras = private
        conf.privateAurasEnabled = nil
        conf.privateAuraMax = nil
        conf.privateAuraSize = nil
        conf.privateAuraAnchor = nil
        conf.privateAuraX = nil
        conf.privateAuraY = nil
        conf.privateAuraCountdown = nil
        changed = true
    elseif type(conf.privateAuras) ~= "table" then
        conf.privateAuras = LegacyPrivateAuraDefaults()
        changed = true
    end
    if type(conf.auras.buff) ~= "table" then conf.auras.buff = LegacyBuffDefaults(); changed = true end
    if type(conf.auras.debuff) ~= "table" then conf.auras.debuff = LegacyDebuffDefaults(); changed = true end
    if type(conf.auras.externals) ~= "table" then conf.auras.externals = LegacyExternalDefaults(); changed = true end
    if conf.auras.iconZoom == nil then conf.auras.iconZoom = 100; changed = true end
    local legacyIconZoom = tonumber(conf.auras.iconZoom) or 100
    if conf.auras.buff.iconZoom == nil then conf.auras.buff.iconZoom = legacyIconZoom; changed = true end
    if conf.auras.debuff.iconZoom == nil then conf.auras.debuff.iconZoom = legacyIconZoom; changed = true end
    FillMissingAuraFields(conf.auras.buff, LEGACY_BUFF_DEFAULTS)
    FillMissingAuraFields(conf.auras.debuff, LEGACY_DEBUFF_DEFAULTS)
    FillMissingAuraFields(conf.auras.externals, LEGACY_EXTERNAL_DEFAULTS)
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, iconZoom = 100, iconScale = 100 }
        changed = true
    end
    if conf.spellIndicators.iconZoom == nil then conf.spellIndicators.iconZoom = 100; changed = true end
    if conf.spellIndicators.iconScale == nil then conf.spellIndicators.iconScale = 100; changed = true end
    local _, spellStyleChanged = GF.EnsureSpellIndicatorStyle(conf)
    changed = spellStyleChanged or changed
    return changed
end

---
--- EnsureDB repair pipeline
---
--- One record per saved scope. `defaults` and `isRaid` are exactly the
--- arguments the former hand-written EnsureDB passed for that scope.
local MEMBER_SCOPES = {
    { key = "gf_party",      kind = "party",      defaults = PARTY_DEFAULTS,       isRaid = false },
    { key = "gf_raid",       kind = "raid",       defaults = RAID_DEFAULTS,        isRaid = true  },
    { key = "gf_mythicraid", kind = "mythicraid", defaults = MYTHIC_RAID_DEFAULTS, isRaid = true  },
}
local PRIORITY_SCOPE = { key = "gf_priority", kind = "priority", defaults = PRIORITY_DEFAULTS, isRaid = false }
local ALL_SCOPES = { MEMBER_SCOPES[1], MEMBER_SCOPES[2], MEMBER_SCOPES[3], PRIORITY_SCOPE }
local PARTY_ONLY = { MEMBER_SCOPES[1] }

--- Ordered repair steps. `run(conf, scope)` is applied to every scope in
--- `scopes` (default: the three member scopes, party -> raid -> mythic raid)
--- before the next step starts. That is the order the hand-written EnsureDB
--- used; several steps read what earlier steps wrote (defaults must be
--- applied before the grid-center and aura steps, the corner-custom type guard
--- must precede the one-shot corner migration), so append new steps at the
--- position they belong and never reorder existing ones.
local DB_REPAIR_STEPS = {
    --- MSUF 6.0 no longer registers aura buttons with Masque. Clear only our
    --- retired profile flag; Masque itself and its other addon groups remain
    --- completely untouched.
    { name = "masque", run = function(conf) conf.masqueEnabled = nil end },
    { name = "fontField", run = NormalizeFontField },
    { name = "showHPTo3Slot", run = MigrateShowHPTo3Slot },
    { name = "highlightUnified", run = MigrateHighlightToUnified },
    --- Defensive: type-guard ciCustom* fields BEFORE the one-shot CI migration
    --- (which may already be stamped done from a previous build).
    { name = "cornerCustomTypes", run = CleanupCornerCustomTypes },
    { name = "cornerIndicators", run = MigrateCornerIndicators },
    { name = "petFrame", run = RemoveGroupPetFrameConfig },
    { name = "layoutPreset", run = RemoveLayoutPresetState },
    { name = "healPredOwnership", run = MigrateHealPredictionOwnership },
    { name = "textureOverrideOwnership", run = MigrateTextureOverrideOwnership },
    { name = "splitDNDStatusText", run = MigrateSplitDNDStatusText },
    --- Party is the only scope that owns portrait config.
    { name = "portraitSizeMode", run = MigratePortraitSizeMode, scopes = PARTY_ONLY },
    { name = "defaults", scopes = ALL_SCOPES,
      run = function(conf, scope) applyDefaults(conf, scope.defaults) end },
    { name = "gridCenterPosition",
      run = function(conf, scope) GF.MigrateGroupPositionToGridCenter(conf, scope.kind) end },
    --- Migrate flat aura keys to nested tables
    { name = "auraConfig",
      run = function(conf, scope)
          if GF.MigrateAuraConfig then GF.MigrateAuraConfig(conf, scope.isRaid) end
      end },
    { name = "menuDomainRepair",
      run = function(conf, scope) GROUP_MENU_DOMAIN_REPAIR.Conf(conf, scope.defaults, scope.isRaid) end },
    { name = "auraRenderer", run = NormalizeAuraRenderer },
    { name = "auraFilters", run = RepairAuraFilters },
    { name = "auraV2", run = RepairAuraV2 },
}

--- Cold body of GF.EnsureDB: materialize the four scope tables, then run every
--- repair step in order. The caller owns the stable-cache fast path, the conf
--- cache refresh and the post-repair bookkeeping.
function GF.RepairGroupDB(db)
    for i = 1, #ALL_SCOPES do
        local key = ALL_SCOPES[i].key
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    for i = 1, #DB_REPAIR_STEPS do
        local step = DB_REPAIR_STEPS[i]
        local scopes = step.scopes or MEMBER_SCOPES
        local run = step.run
        for j = 1, #scopes do
            local scope = scopes[j]
            run(db[scope.key], scope, db)
        end
    end
end

--- Public ABI (profile import/export call it by global name); keep exported.
ExportPublic("MSUF_GF_MigrateAuraConfig", GF.MigrateAuraConfig)
