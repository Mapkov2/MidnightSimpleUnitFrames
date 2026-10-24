-- Fresh-install factory construction and factory baseline repairs.
local _, MSUF = ...
local Parts = MSUF.DefaultsParts
local IS_CLASSIC_FAMILY = Parts.IS_CLASSIC_FAMILY
local MSUF_DEFAULTS_GROUP_AURA_SCOPES = Parts.MSUF_DEFAULTS_GROUP_AURA_SCOPES
local MSUF_DEFAULTS_GROUP_SCOPE_KEYS = Parts.MSUF_DEFAULTS_GROUP_SCOPE_KEYS
local MSUF_DEFAULTS_TEXT_SCOPE_KEYS = Parts.MSUF_DEFAULTS_TEXT_SCOPE_KEYS
local MSUF_DEFAULT_BOSS_OFFSET_X = Parts.MSUF_DEFAULT_BOSS_OFFSET_X
local MSUF_DEFAULT_BOSS_OFFSET_Y = Parts.MSUF_DEFAULT_BOSS_OFFSET_Y
local MSUF_Defaults_ApplyPredictionBarBaseline = Parts.MSUF_Defaults_ApplyPredictionBarBaseline
local MSUF_Defaults_CreateCanonicalGroupAuraState = Parts.MSUF_Defaults_CreateCanonicalGroupAuraState
local MSUF_Defaults_CreateFactoryUnitAuras = Parts.MSUF_Defaults_CreateFactoryUnitAuras
local MSUF_Defaults_DeepCopy = Parts.MSUF_Defaults_DeepCopy
local MSUF_Defaults_GetGlobalFontDefault = Parts.MSUF_Defaults_GetGlobalFontDefault
local MSUF_Defaults_GetMenuFontDefault = Parts.MSUF_Defaults_GetMenuFontDefault
local MSUF_Defaults_GetProfilePayload = Parts.MSUF_Defaults_GetProfilePayload
local MSUF_Defaults_NormalizePortraitRenderDB = Parts.MSUF_Defaults_NormalizePortraitRenderDB
local MSUF_Defaults_NormalizeProfileTo60Defaults = Parts.MSUF_Defaults_NormalizeProfileTo60Defaults
local MSUF_Defaults_TryDecodeCompactString = Parts.MSUF_Defaults_TryDecodeCompactString
local MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED = Parts.MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED
local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = Parts.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
local fresh = Parts.fresh
function fresh.EnsureUnitAlphaDefaults(conf)
    if not conf then  return end
    MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.CoreHpBarAlpha001)
    if conf.powerBarBgAlpha == nil then conf.powerBarBgAlpha = conf.hpBgAlpha or 0.85 end
    MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.CoreAlphaExcludeTextPortrait002)
end
function fresh.EnsureFreshUnitframeScreenPosition(conf, x, y)
    if type(conf) ~= "table" then return end
    if conf.anchorFrameName == nil and conf.anchorToUnitframe == nil then
        MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.FactoryConfAnchorToUnitframe, true)
    end
    if conf.offsetX == nil then conf.offsetX = x end
    if conf.offsetY == nil then conf.offsetY = y end
end
function fresh.EnsureFreshGroupAuraNativeRenderer(conf)
    if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
    local auras = conf.auras
    MSUF.DefaultsSchema.Fill(auras, MSUF.DefaultsSchema.Values.FreshRenderer)
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    local types = auras.blizzardTypes
    MSUF.DefaultsSchema.Fill(types, MSUF.DefaultsSchema.Values.FreshBuffs)
    MSUF.DefaultsSchema.Fill(auras, MSUF.DefaultsSchema.Values.FreshBlizzardIconSize)
    for _, key in ipairs({ "buff", "debuff", "externals" }) do
        if type(auras[key]) ~= "table" then auras[key] = {} end
        MSUF.DefaultsSchema.Fill(auras[key], MSUF.DefaultsSchema.Values.FreshStrata)
        if key == "buff" then MSUF.DefaultsSchema.Fill(auras[key], MSUF.DefaultsSchema.Values.FreshTrackedStrata) end
        MSUF.DefaultsSchema.Fill(auras[key], MSUF.DefaultsSchema.Values.FreshCooldownSwipeReverse)
        if type(auras[key].blacklist) ~= "table" then auras[key].blacklist = {} end
        if type(auras[key].blacklist.spells) ~= "table" then auras[key].blacklist.spells = {} end
        MSUF.DefaultsSchema.Fill(auras[key].blacklist, MSUF.DefaultsSchema.Values.FreshHidePermanent)
    end
end

function fresh.Bars(db)
    db.bars = db.bars or {}
    MSUF.DefaultsSchema.Fill(db.bars, MSUF.DefaultsSchema.Values.FreshShowAltMana)
    -- Performance baseline: native interpolation is an
    -- explicit visual option, never an implicit cost on a fresh profile.
    MSUF.DefaultsSchema.Fill(db.bars, MSUF.DefaultsSchema.Values.FactoryDbbarsSmoothPowerBar, true)
    --- Not adopted on Classic: its fresh profiles have never carried this key,
    --- and the shared bars stage seeds it to false anyway when it is missing.
    if not IS_CLASSIC_FAMILY then
        MSUF.DefaultsSchema.Fill(db.bars, MSUF.DefaultsSchema.Values.FactoryDbbarsChunkedPowerBar, true)
    end
    MSUF.DefaultsSchema.Fill(db.bars, MSUF.DefaultsSchema.Values.FactoryDbbarsClassPowerSmoothFill, true)
    for _, key in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
        if type(db[key]) == "table" then
            MSUF.DefaultsSchema.Fill(db[key], MSUF.DefaultsSchema.Values.FactoryDbkeySmoothFill, true)
        end
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        if type(db[key]) == "table" then
            MSUF.DefaultsSchema.Fill(db[key], MSUF.DefaultsSchema.Values.FactoryDbkeySmoothFill, true)
            -- Secure headers enforce this cap after a page reset too.
            if key == "gf_raid" then db[key].maxColumns = 8 end
        end
    end
    if type(db.gf_party) ~= "table" then db.gf_party = {} end
    MSUF.DefaultsSchema.Fill(db.gf_party, MSUF.DefaultsSchema.Values.FactoryDbgfpartyEnabled, true)
    if type(db.focustarget) ~= "table" then db.focustarget = {} end
    MSUF.DefaultsSchema.Fill(db.focustarget, MSUF.DefaultsSchema.Values.FactoryDbfocustargetEnabled, true)
    MSUF.DefaultsSchema.Fill(db.bars, MSUF.DefaultsSchema.Values.FreshRoundedFramesEnabled)
end

function fresh.Shell(db)
    --- Fresh-install defaults: status indicators (AFK/DND) off by default
    local g = db.general
    if type(g) == 'table' then
        if type(g.statusIndicators) ~= "table" then g.statusIndicators = {} end
        local si = g.statusIndicators
        MSUF.DefaultsSchema.Fill(si, MSUF.DefaultsSchema.Values.FreshShowAFK)

        --- Fresh-install scaling defaults:
        --- Match Unhalted-style global UI scale: disabled until the user enables it.
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FreshAnchorToCooldown)
        if type(g.UIScale) ~= "table" then
            g.UIScale = { Enabled = false, Scale = 1.0 }
        else
            MSUF.DefaultsSchema.Fill(g.UIScale, MSUF.DefaultsSchema.Values.FreshEnabled)
        end
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryGSlashMenuScale, true)
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FreshMsufUiScale)
        --- English/German use MSUF's highly readable UI face. Other locales
        --- retain Blizzard's locale-specific glyph coverage.
        g.fontKey = MSUF_Defaults_GetGlobalFontDefault()
        --- Fresh installs use MSUF's bundled, tint-neutral premium bar surface.
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryGBarTexture, true)
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FreshUnitTooltipProvider)
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryG_msufPreviewDragHintExperienced, true)
        -- Start previews clean; the Guides layer is an explicit user choice.
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryGUnitPreviewGuidesEnabled, true)
        --- Factory Edit Mode baseline: grid on at 36px with snap, backdrop
        --- dimmed to 55%. The compact snapshot predates these tuned values,
        --- so they are set unconditionally over its stale ones.
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryGEditModeGridEnabled, true)
        --- Factory castbars fill left to right. The snapshot carries the
        --- exporter's own choice, and the nil-key default stays RTL so
        --- existing profiles keep their direction.
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryGCastbarFillDirection, true)
        --- Factory cleanse border lights up for what the group can dispel,
        --- not for every debuff that carries a dispel type.
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryGDispelBorderTrigger, true)
        g.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
        MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.FactoryG_msufFactoryNameShorteningFixed_v1, true)
    end
    MSUF_Defaults_NormalizePortraitRenderDB(db)
end

local function MSUF_Defaults_ApplyFreshInstallOverrides(db)
    if not db then  return end


    MSUF_Defaults_ApplyPredictionBarBaseline(db)

    --- Unified alpha defaults: HP fill opacity, power fill opacity, background
    --- texture opacity, plus opt-in exclusions for informational frame elements.
    --- Group frames still use the HP/background subset plus prediction exclusion.

    fresh.EnsureUnitAlphaDefaults(db.player)
    --- Fresh-install default: player name hidden
    if type(db.player) == "table" then
        MSUF.DefaultsSchema.Fill(db.player, MSUF.DefaultsSchema.Values.FreshShowName)
    end
    fresh.EnsureUnitAlphaDefaults(db.target)
    fresh.EnsureUnitAlphaDefaults(db.focus)
    fresh.EnsureUnitAlphaDefaults(db.focustarget)
    fresh.EnsureUnitAlphaDefaults(db.pettarget)
    fresh.EnsureUnitAlphaDefaults(db.pet)
    fresh.EnsureUnitAlphaDefaults(db.boss)
    fresh.EnsureUnitAlphaDefaults(db.targettarget)
    fresh.EnsureUnitAlphaDefaults(db.tot)
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        MSUF.DefaultsSchema.Fill(db[key], MSUF.DefaultsSchema.Values.FreshAlphaExcludePredictionBars)
        --- Raid/Mythic-only sorting toggle, seeded on every group scope like the
        --- GroupFrames PARTY_DEFAULTS so the factory snapshot carries it explicitly.
        MSUF.DefaultsSchema.Fill(db[key], MSUF.DefaultsSchema.Values.FreshSortRolesAcrossRaid)
    end
    --- Older exports may omit screen positions; in that case provide stable
    --- center anchors without touching positions included by the compact export.
    fresh.EnsureFreshUnitframeScreenPosition(db.player, -260, 80)
    fresh.EnsureFreshUnitframeScreenPosition(db.target, 260, 80)
    fresh.EnsureFreshUnitframeScreenPosition(db.focus, 260, 135)
    fresh.EnsureFreshUnitframeScreenPosition(db.focustarget, 260, 180)
    fresh.EnsureFreshUnitframeScreenPosition(db.pettarget, -275, -290)
    fresh.EnsureFreshUnitframeScreenPosition(db.pet, -260, 135)
    fresh.EnsureFreshUnitframeScreenPosition(db.targettarget or db.tot, 260, 225)
    fresh.EnsureFreshUnitframeScreenPosition(db.boss, MSUF_DEFAULT_BOSS_OFFSET_X, MSUF_DEFAULT_BOSS_OFFSET_Y)
    fresh.EnsureFreshGroupAuraNativeRenderer(db.gf_party)
    fresh.EnsureFreshGroupAuraNativeRenderer(db.gf_raid)
    fresh.EnsureFreshGroupAuraNativeRenderer(db.gf_mythicraid)
    --- Factory profiles keep every frame's health coloring linked to the
    --- shared Global Style instead of carrying per-frame color overrides.
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            db[key].healthColorMode = nil
        end
    end
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            db[key].gfBarMode = nil
        end
    end
    --- Factory-only dispel-symbol policy. "Symbol detects" is owned by the
    --- Unit/Group frame roots, not by the Aura lane filter tables. Override
    --- every scope carried by the factory snapshot so a stale local value
    --- cannot mask the shared "Removable by me" baseline.
    if type(db.general) == "table" then
        MSUF.DefaultsSchema.Fill(db.general, MSUF.DefaultsSchema.Values.FactoryDbgeneralUnitDispelSymbolTrigger, true)
    end
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            MSUF.DefaultsSchema.Fill(db[key], MSUF.DefaultsSchema.Values.FactoryDbkeyUnitDispelSymbolTrigger, true)
        end
    end
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            MSUF.DefaultsSchema.Fill(db[key], MSUF.DefaultsSchema.Values.FactoryDbkeyDispelSymbolTrigger, true)
        end
    end
    fresh.Bars(db)
    fresh.Shell(db)
end

--- Canonical Unit Aura baseline for the one-time 6.0 Aura reset and for the
--- no-payload fallback. Factory profiles apply a separate explicit overlay
--- below so product positioning can evolve without changing hard-cut geometry.
--- Classic stayed on model revision 1: every profile its builds ever saved
--- carries that number, and the sparse-owner repair below only recognises a
--- profile at the revision it is stamped with. Bumping it on Classic would
--- re-run the legacy aura migrations over settled profiles.
local MSUF_FOREVER_HEALTH_UNITS = {
    "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
    "gf_party", "gf_raid", "gf_mythicraid",
}

local function MSUF_Defaults_MuteForeverHealth(profileDB, freshFactory)
    if not (MSUF.Client.IsForever) then return end
    local g = profileDB.general
    if type(g) ~= "table" or g._msufForeverMutedHealth_v1 then return end
    -- Unhalted's health fill starts at 80% opacity. Apply that to the Forever
    -- factory; on stored factory profiles only replace the old 90% baseline.
    for i = 1, #MSUF_FOREVER_HEALTH_UNITS do
        local conf = profileDB[MSUF_FOREVER_HEALTH_UNITS[i]]
        if type(conf) == "table" then
            local alpha = tonumber(conf.hpBarAlpha)
            if freshFactory or (g._msufFactoryProfileApplied == true
                and alpha and math.abs(alpha - 0.9) < 0.001) then
                conf.hpBarAlpha = 0.8
            end
        end
    end
    g._msufForeverMutedHealth_v1 = true
end

local function MSUF_Defaults_CreateFactoryProfile()
    -- Prefer the shared codec once it has loaded: it inflates before CBOR, the
    -- same order Blizzard uses. The local decoder is only the pre-codec fallback.
    local decode = _G.MSUF_TryDecodeCompactString
    if type(decode) ~= "function" then
        decode = MSUF_Defaults_TryDecodeCompactString
    end
    local tbl = decode(MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    if not tbl then  return nil end
    if MSUF.Client.IsForever then
        if tbl.addon ~= "MSUF" or tonumber(tbl.fmt) ~= 2
            or type(tbl.msuf6) ~= "table" or tonumber(tbl.msuf6.schema) ~= 600 then
            return nil
        end
        local native = tbl.msuf6.payload
        if type(native) ~= "table" then return nil end
        local out = {}
        MSUF_Defaults_DeepCopy(out, native)
        out.general = out.general or {}
        out.general._msufFactoryProfileApplied = true
        out.general.fontKey = MSUF_Defaults_GetGlobalFontDefault()
        out.general.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
        return MSUF.ProfileMigrations.Apply(out)
    end
    local payload = MSUF_Defaults_GetProfilePayload(tbl)
    if type(payload) ~= "table" then  return nil end

    local out = {}
    MSUF_Defaults_DeepCopy(out, payload)
    --- The portable payload predates the Focus Target frame and has no table for
    --- it. A current export carries that frame in its native 6.0 section, so take
    --- it from there instead of falling back to the code defaults.
    if out.focustarget == nil and type(tbl.msuf6) == "table" and type(tbl.msuf6.payload) == "table"
        and type(tbl.msuf6.payload.focustarget) == "table" then
        out.focustarget = {}
        MSUF_Defaults_DeepCopy(out.focustarget, tbl.msuf6.payload.focustarget)
    end
    MSUF_Defaults_ApplyFreshInstallOverrides(out)
    --- The compact factory snapshot intentionally remains portable to older
    --- releases and therefore still contains Aura2 compatibility data. Fresh
    --- 6.0 profiles use the explicit native factory variant, never that
    --- compatibility payload or the migration-only hard-cut geometry.
    out.auras = nil
    out.auras2 = nil
    out.auras3 = MSUF_Defaults_CreateFactoryUnitAuras()
    local groupAuraState = MSUF_Defaults_CreateCanonicalGroupAuraState()
    if type(groupAuraState) == "table" then
        for i = 1, #MSUF_DEFAULTS_GROUP_AURA_SCOPES do
            local scope = MSUF_DEFAULTS_GROUP_AURA_SCOPES[i]
            local state = groupAuraState[scope]
            local conf = type(out[scope]) == "table" and out[scope] or {}
            out[scope] = conf
            if type(state) == "table" then
                conf.auras = state.auras
                conf.privateAuras = state.privateAuras
                conf.spellIndicators = state.spellIndicators
            end
        end
    end
    MSUF_Defaults_NormalizeProfileTo60Defaults(out)
    --- The compact snapshot predates the shared Appearance products, and its
    --- Player Defensive container replaces the portrait (portraitIcon = true).
    --- Factory baselines therefore follow the frame portrait shape instead of
    --- inheriting the rectangular legacy fallback.
    if type(out.auras3) == "table" then
        local auraShared = type(out.auras3.shared) == "table" and out.auras3.shared or {}
        out.auras3.shared = auraShared
        local shapes = type(auraShared.appearanceIconShapes) == "table" and auraShared.appearanceIconShapes or {}
        auraShared.appearanceIconShapes = shapes
        MSUF.DefaultsSchema.Fill(shapes, MSUF.DefaultsSchema.Values.CorePlayerDefensives003)
    end
    -- Classic factory policy runs only after the authored unit/group aura
    -- owners exist. New/reset profiles get it; saved layouts and the legacy
    -- sparse-owner repair keep their original geometry. Midnight is unchanged.
    if IS_CLASSIC_FAMILY or (MSUF.Client.IsForever) then
        out.bars.powerBarHeight = 7
        out.bars.classPowerHeight = 8
        out.bars.showAltMana = true
        out.bars.altManaHeight = 6
        -- Class power ends 11 px below the 40 px player frame. Leave a gap
        -- before the optional mana bar so druid forms can show both resources.
        out.bars.altManaOffsetY = -14
        for _, key in ipairs({ "player", "target", "focus", "pet", "boss", "arena" }) do
            local conf = out[key]
            if type(conf) == "table" then
                conf.powerBarHeight = (key == "player" or key == "target") and 7 or 6
            end
        end

        local raid = out.gf_raid
        raid.width, raid.height, raid.spacing = 110, 44, 4
        raid.unitsPerColumn, raid.maxColumns = 5, 8
        raid.preserveRaidGroups = true
        raid.growth, raid.groupGrowth = "DOWN", "RIGHT"
        raid.point, raid.relativePoint = "TOPLEFT", nil
        raid.anchorToFrame = "UIParent"
        raid.offsetX, raid.offsetY = 24, -160
        raid.positionMode = "GRID_BOUNDS_V2"

        for _, key in ipairs({ "gf_party", "gf_raid" }) do
            local conf = out[key]
            local isRaid = key == "gf_raid"
            conf.hpFontSize, conf.threatTextSize = 11, 11
            conf.powerBarEnabled = true
            conf.powerShowTank, conf.powerShowHealer, conf.powerShowDamager = true, true, true
            conf.powerHeight = 6
            -- Reserve the upper line for names/health, the lower line for
            -- auras, and the top edge of party frames for threat percentage.
            conf.nameAnchor, conf.nameOffsetX = "LEFT", 12
            conf.nameOffsetY = isRaid and 8 or 7
            conf.textLeft, conf.textCenter, conf.textRight = "NONE", "NONE", "PERCENT"
            conf.hpOffsetX, conf.hpOffsetY = -12, isRaid and 8 or 7
            local auras = conf.auras
            local debuff = auras.debuff
            debuff.max, debuff.perRow, debuff.spacing = 3, 3, 2
            debuff.dispelBorderMode = "SYMBOL"
            debuff.y = 8
            auras.externals.y = 8
            -- Keep the existing buff highlight beside, rather than over,
            -- the expanded debuff row. All rows clear the six-pixel mana bar.
            auras.buff.anchor, auras.buff.growth = "BOTTOMRIGHT", "LEFTUP"
            auras.buff.x, auras.buff.y = -2, 8
        end

        for _, unit in ipairs({ "player", "target" }) do
            local owner = out.auras3.perUnit[unit]
            local layout, shared = owner.layout, owner.layoutShared
            layout.buffGroupOffsetX, layout.buffGroupOffsetY = 0, 44
            layout.debuffGroupOffsetX, layout.debuffGroupOffsetY = 0, 44
            layout.buffGroupIconSize, layout.debuffGroupIconSize = 26, 26
            layout.buffSpacing, layout.debuffSpacing = 2, 2
            shared.maxDebuffs = unit == "target" and 8 or 6
            shared.debuffPerRow = unit == "target" and 4 or 3
            shared.debuffGrowthX, shared.debuffGrowthY = "LEFT", "UP"
            shared.debuffTypeBorderMode = "SYMBOL"
            shared.useDebuffTypeBorders = true
            -- DEFAULT already sorts own auras first on Classic. Keep all
            -- casters eligible so another player's crowd control can appear.
            shared.debuffSortMethod = "DEFAULT"
        end
    end
    out.general = out.general or {}
    out.general._msufFactoryProfileApplied = true
    out._msufFactoryPlayerDefensivesEnabled_v1 = MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED
    return MSUF.ProfileMigrations.Apply(out)
end
local MSUF_DEFAULTS_FACTORY_BOOTSTRAP_ROOTS = {
    gameplay = true,
    general = true,
    _msufProfileSchema = true,
    _msufProfileNormalizationRevision = true,
}
local MSUF_DEFAULTS_FACTORY_BOOTSTRAP_GENERAL_KEYS = {
    fontBaselineOffset = true,
    minimapIconDB = true,
    showGameMenuButton = true,
    showMinimapIcon = true,
    previewDragHintAnimationEnabled = true,
    --- Written by the profile init (State/MSUF_Profiles.lua) on every profile
    --- that lacks it, brand-new ones included; the factory profile resets it.
    _msufPreviewDragHintExperienced = true,
}
local function MSUF_Defaults_TableHasOnlyAllowedKeys(tbl, allowed)
    if type(tbl) ~= "table" then return false end
    for key in pairs(tbl) do
        if not allowed[key] then
            return false
        end
    end
    return true
end
local function MSUF_Defaults_IsFreshInstallProfileDB(db)
    if type(db) ~= "table" then return false end
    if next(db) == nil then return true end

    local g = (type(db.general) == "table") and db.general or nil
    if g and g._msufFactoryProfileApplied then
        return false
    end

    --- On a true first login, startup modules registered before the UF factory
    --- may create harmless roots such as gameplay/general before EnsureDB runs.
    --- Treat only that pre-seed shape as fresh; any unit/config root means this
    --- profile already has real saved data and must not be overwritten.
    for key, value in pairs(db) do
        if not MSUF_DEFAULTS_FACTORY_BOOTSTRAP_ROOTS[key] then
            return false
        end
        if key == "general"
            and not MSUF_Defaults_TableHasOnlyAllowedKeys(value, MSUF_DEFAULTS_FACTORY_BOOTSTRAP_GENERAL_KEYS) then
            return false
        end
    end
    return true
end
local function MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall(profileDB)
    if type(profileDB) ~= "table" then  return end
    local g = (type(profileDB.general) == "table") and profileDB.general or nil
    if g and g._msufFactoryProfileApplied then
         return
    end
    if not MSUF_Defaults_IsFreshInstallProfileDB(profileDB) then return end
    local payload = MSUF_Defaults_CreateFactoryProfile()
    if type(payload) ~= "table" then  return end
    --- Overlay the fresh DB with the decoded payload. DeepCopy replaces known
    --- payload tables and leaves unrelated future bootstrap buckets intact.
    MSUF_Defaults_DeepCopy(profileDB, payload)
end
local function MSUF_Defaults_RepairFactoryNameShortening(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufFactoryProfileApplied == true) then return false end

    --- Modern factory snapshots already contain their intended name settings.
    --- A factory marker is provenance for the original seed, not proof that
    --- every value is still factory-owned: users may have customized any of
    --- these fields before this migration marker existed. Complete the
    --- migration without rewriting divergent SavedVariables.
    if g._msufModernFactoryProfile_v1 == true then
        if g._msufModernFactoryNameShortening_v2 == true then return false end
        g._msufModernFactoryNameShortening_v2 = true
        return false
    end

    local looksLikeFactoryShortening = db.shortenNames == true
        and tonumber(g.shortenNameMaxChars) == 8
        and tostring(g.shortenNameClipSide or ""):upper() == "RIGHT"
        and g.shortenNameShowDots == false
    if g._msufFactoryNameShorteningFixed_v1 == true
        and g._msufFactoryScopedNameShorteningFixed_v1 == true then
        return false
    end
    local changed = false
    if g._msufFactoryNameShorteningFixed_v1 ~= true or looksLikeFactoryShortening then
        if looksLikeFactoryShortening then
            db.shortenNames = false
            changed = true
        end
        g._msufFactoryNameShorteningFixed_v1 = true
    end
    if g._msufFactoryScopedNameShorteningFixed_v1 ~= true then
        --- Scoped values have no complete old-factory signature. Preserve them
        --- instead of treating any enabled scope as proof of factory ownership.
        g._msufFactoryScopedNameShorteningFixed_v1 = true
    end
    return changed
end

local function MSUF_Defaults_RepairModernFactoryPlayerStack(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufModernFactoryProfile_v1 == true)
        or g._msufModernFactoryPlayerStack_v1 == true then
        return false
    end

    local changed = false
    local player = type(db.player) == "table" and db.player or nil
    --- v23 placed the 16 px Player castbar over the detached 8 px powerbar:
    --- frame bottom -> power Y -6..-14, castbar top -> Y -4. Only repair that
    --- exact factory geometry so a manually moved castbar stays untouched.
    if player
        and player.powerBarDetached == true
        and tonumber(player.detachedPowerBarHeight) == 8
        and tonumber(player.detachedPowerBarOffsetY) == -6
        and tonumber(g.castbarPlayerBarHeight) == 16
        and tonumber(g.castbarPlayerOffsetY) == -48 then
        g.castbarPlayerOffsetY = -64
        changed = true
    end
    g._msufModernFactoryPlayerStack_v1 = true
    return changed
end

local function MSUF_Defaults_RepairModernFactoryNamePresentation(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufModernFactoryProfile_v1 == true)
        or g._msufModernFactoryNamePresentation_v1 == true then
        return false
    end

    --- The refreshed embedded factory profile already has these values. Older
    --- profiles may have diverged legitimately, so this one-shot marker must
    --- never act as a broad overwrite transaction.
    g._msufModernFactoryNamePresentation_v1 = true
    return false
end


Parts.MSUF_Defaults_CreateFactoryProfile = MSUF_Defaults_CreateFactoryProfile
Parts.MSUF_Defaults_IsFreshInstallProfileDB = MSUF_Defaults_IsFreshInstallProfileDB
Parts.MSUF_Defaults_MuteForeverHealth = MSUF_Defaults_MuteForeverHealth
Parts.MSUF_Defaults_RepairFactoryNameShortening = MSUF_Defaults_RepairFactoryNameShortening
Parts.MSUF_Defaults_RepairModernFactoryNamePresentation = MSUF_Defaults_RepairModernFactoryNamePresentation
Parts.MSUF_Defaults_RepairModernFactoryPlayerStack = MSUF_Defaults_RepairModernFactoryPlayerStack
Parts.MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall = MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall
