-- Declarations derive profile setters; existing bindings own history and combat refusal.
local _, MSUF = ...
local M = MSUF.MSUF2
local W = M.Widgets
local Schema = {}
M.ControlSchema = Schema

-- UI compatibility owns the old page fallbacks, not profile normalization.
-- Reading a declaration never seeds a saved key or repairs a partial import.
local UI_DEFAULTS = {
    gameplay = {
        combatTimerAnchor = "none", combatFontSize = 24, lockCombatTimer = false, combatTimerClickThrough = false,
        combatOffsetX = 0, combatOffsetY = -200, lockCombatState = false, combatStateFontSize = 24,
        combatStateDuration = 1.5, combatStateOffsetX = 0, combatStateOffsetY = 80,
        playerTotemsIconSize = 24, playerTotemsOffsetX = 0, playerTotemsOffsetY = -6,
        playerTotemsAnchorFrom = "TOPLEFT", playerTotemsAnchorTo = "BOTTOMLEFT", crosshairThickness = 3, crosshairSize = 40,
        enableCombatTimer = false, enableCombatStateText = false, enablePlayerTotems = false,
        enableCombatCrosshair = false, enableCombatCrosshairMeleeRangeColor = false,
        meleeSpellPerClass = false, meleeSpellPerSpec = false, combatStateEnterText = "+Combat", combatStateLeaveText = "-Combat",
    },
    unit = {
        hpBarAlpha = 1, hpBgAlpha = 0.85, powerBarAlpha = 1, powerBarBgAlpha = 0.85,
        alphaExcludeTextPortrait = false, alphaExcludePredictionBars = false, oocFadeEnabled = false, oocFadeAlpha = 0.5,
        rangeFadeEnabled = true, rangeFadeAlpha = 0.4, rangeFadeUpdateRate = 0, rangeFadeLayerMode = "frame",
    },
    bars = {
        showIgnorePain = false, showArcaneWindow = false, arcaneWindowTextFrom = 0, arcaneWindowWarnLastGCD = false,
        manaRegenPause = false, manaGainPulse = false, manaUpcomingCost = false, resourceExtraOffsetX = 0,
    },
}
local EXTRA_DEFAULTS = MSUF.CPBuilders.ExtraAuraDefaults
Schema.MarkDefaults = { target = "PLAYER", resource = "ALL", mode = "PERCENT", value = 50,
    width = 2, color = { 1, 1, 1 }, mark = true }
function Schema.Default(scope, key)
    local store = UI_DEFAULTS[scope] or UI_DEFAULTS.unit
    local value = store[key]
    if value == nil and scope == "bars" then value = EXTRA_DEFAULTS[key] end
    assert(value ~= nil, "legacy UI default missing: " .. scope .. "." .. key)
    return value
end

-- These flags preserve the current ApplyService interface. No reason-text inference
-- or pending core-domain implementation is introduced by the pilot.
local UNIT_DOMAINS = {
    alpha = { alpha = true, preview = true },
    background = { preview = true },
    powerAlpha = { power = true, preview = true },
    oocAlpha = { alpha = true },
    range = { preview = true },
    arenaTrinket = { preview = true },
    layout = { preview = true },
}
function Schema.SetUnit(domain, unit, key, value, reason, kind)
    local flags = assert(UNIT_DOMAINS[domain], "unknown pilot unit apply domain")
    local owner = M.UnitPage
    if kind == "toggle" then return owner.SetBool(unit, key, value, reason, flags) end
    if kind == "slider" then return owner.SetNumber(unit, key, value, reason, flags) end
    return owner.SetString(unit, key, value, reason, flags)
end

-- Physical setting declarations are shared by write accessors and reset targets.
-- The existing binder retains history scopes, input bounds and combat refusal.
function Schema.AuraLaneSchema() return MSUF.MSUF_Auras3.LaneKeySchema end
function Schema.Family(keys, resolve, patterns)
    return { keys = keys, resolve = resolve, patterns = patterns }
end
function Schema.GroupKeys(key)
    return Schema.Family({ "gf_party." .. key, "gf_raid." .. key, "gf_mythicraid." .. key })
end
function Schema.Record(paths)
    local patterns = {}
    for _, path in ipairs(paths) do
        patterns[#patterns + 1] = "^" .. path:gsub("([^%w])", "%%%1"):gsub("%%{[^}]+%%}", "[^.]+") .. "$"
    end
    return { recordPaths = paths, patterns = patterns }
end
function Schema.Fields(owners, fields)
    local paths = {}
    for _, owner in ipairs(owners) do
        for _, field in ipairs(fields) do paths[#paths + 1] = owner .. "." .. field end
    end
    return Schema.Record(paths)
end
function Schema.TextSlots(unit, kind, field)
    local keys = {}
    local function Add(key)
        if unit == "group" then
            for _, path in ipairs(Schema.GroupKeys(key).keys) do keys[#keys + 1] = path end
        else keys[#keys + 1] = unit .. "." .. key end
    end
    for _, slot in ipairs({ "Left", "Center", "Right" }) do
        local key = (kind == "hp" and "text" or "powerText") .. slot
        if field == "size" then key = kind .. "Text" .. slot .. "FontSize"
        elseif field == "hide_percent" then key = kind .. "Text" .. slot .. "HidePercentSymbol" end
        Add(key)
        if field == "absorb" then Add("hpText" .. slot .. "AbsorbIcon") end
    end
    return Schema.Family(keys)
end
function Schema.Matches(setting, path)
    if type(setting) == "string" then return setting == path end
    if type(setting) ~= "table" then return false end
    for _, key in ipairs(setting.keys or {}) do if key == path then return true end end
    for _, pattern in ipairs(setting.patterns or {}) do if path:match(pattern) then return true end end
    return false
end
-- A command's physical writes are separate from its search route. Snapshot the
-- declaration so later widget reuse or metadata changes cannot widen it.
-- Record paths name the subtree replaced by an atomic record/account command.
function Schema.Writes(setting, menuState)
    local writes = { keys = {}, patterns = {}, menuState = menuState == true }
    if type(setting) == "string" then writes.keys[1] = setting
    elseif type(setting) == "table" then
        for _, path in ipairs(setting.keys or setting.recordPaths or {}) do writes.keys[#writes.keys + 1] = path end
        for _, pattern in ipairs(setting.patterns or {}) do writes.patterns[#writes.patterns + 1] = pattern end
    end
    return writes
end
function Schema.MatchesWrite(spec, path)
    local writes = assert(spec.writes, "schema write contract missing: " .. tostring(spec.id))
    if writes.menuState then return false end
    while path do
        if Schema.Matches(writes, path) then return true end
        path = path:match("^(.*)%.[^.]+$")
    end
    return false
end
local function WriteContract(spec, menuState)
    local meta = spec.meta or {}
    local command = meta.command or {}
    local targets = spec.writeTargets or meta.writeTargets or command.writeTargets
    menuState = menuState and not targets
    local writes = Schema.Writes(targets or spec.setting, menuState)
    if not menuState then
        for _, path in ipairs(spec.companionWrites or meta.companionWrites or command.companionWrites or {}) do
            writes.keys[#writes.keys + 1] = path
            if path:find("{", 1, true) then
                writes.patterns[#writes.patterns + 1] = Schema.Record({ path }).patterns[1]
            end
        end
    end
    return writes
end
local function PublishWrites(widget, spec)
    local record = widget._msuf2RuntimeControlRecord
    if record and record.controlId == spec.id then record.writes = spec.writes end
end
-- Composite owners refine an existing declaration after attaching the widget.
-- Keep its search target and concrete write snapshot in the same operation.
function Schema.SetSetting(widget, setting)
    local spec = assert(widget._msuf2ControlSchema, "schema composite declaration missing")
    spec.setting = setting
    if setting then spec.ephemeralReason = nil end
    spec.writes = WriteContract(spec, not setting)
    PublishWrites(widget, spec)
    return widget
end
local UNIT_SCOPE_ROOTS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local GROUP_SCOPE_ROOTS = { "gf_party", "gf_raid", "gf_mythicraid" }
function Schema.ScopedFields(fields, shared, flag, groupFields)
    local keys = {}
    local function Add(root, names, scoped)
        for _, field in ipairs(names) do
            keys[#keys + 1] = root == "" and field or root .. "." .. field
            if scoped and (field:match("^[Pp]owerGradient") or field:match("^gradient")
                or field:match("BarGradientColor") or field == "enableGradient" or field == "enablePowerGradient") then
                for _, name in ipairs({ "gradientOverride", "gradientOverrideVersion", "gradientOverrideKeys." .. field }) do
                    keys[#keys + 1] = root .. "." .. name
                end
            end
        end
        if scoped and flag then keys[#keys + 1] = root .. "." .. flag end
    end
    if shared then Add(shared, fields, false) end
    for _, root in ipairs(UNIT_SCOPE_ROOTS) do Add(root, fields, true) end
    for _, root in ipairs(GROUP_SCOPE_ROOTS) do Add(root, groupFields or fields, true) end
    return Schema.Family(keys)
end
-- Scope route aliases are retained for search. Physical declarations use the
-- storage fields of the same scoped writer, including its ownership markers.
local function NormalizeScopeTargets(setting)
    if type(setting) ~= "table" then return setting end
    local keys, patterns = {}, {}
    for _, key in ipairs(setting.keys or {}) do keys[#keys + 1] = key end
    for _, pattern in ipairs(setting.patterns or {}) do
        if pattern:match("^%^barScope") then
            local field = pattern:match(".*%%%.(.-)%$$")
            local base = field and field:match("^(.-)%[RGB%]$")
            for _, suffix in ipairs(base and { "R", "G", "B" } or { "" }) do
                for _, key in ipairs(Schema.ScopedFields({ (base or field) .. suffix }, "general", "hlOverride").keys) do
                    keys[#keys + 1] = key
                end
            end
        else patterns[#patterns + 1] = pattern end
    end
    return Schema.Family(keys, setting.resolve, patterns)
end
function Schema.FromMeta(meta)
    if not meta then return nil end
    if meta.setting then return meta.setting end
    if meta.searchSettingKeys or meta.searchSettingKeyPatterns then
        return NormalizeScopeTargets(Schema.Family(meta.searchSettingKeys, nil, meta.searchSettingKeyPatterns))
    end
    return meta.settingKey
end
-- Named commands retain their existing execution/history owners. Atomic resets
-- and account operations may replace a complete profile or storage subtree.
local function ColorTargets(prefixes, channels, targets)
    targets = targets or {}
    for _, prefix in ipairs(prefixes) do
        for index = 1, #channels do targets[#targets + 1] = prefix .. channels:sub(index, index) end
    end
    return targets
end
local PORTRAIT_RESET_TARGETS = Schema.Fields({ "general", "player", "target", "focus", "targettarget",
    "focustarget", "pet", "pettarget", "boss" }, { "portraitBorderColorR", "portraitBorderColorG", "portraitBorderColorB",
    "portraitBgColorR", "portraitBgColorG", "portraitBgColorB" }).recordPaths
PORTRAIT_RESET_TARGETS[#PORTRAIT_RESET_TARGETS + 1] = "general.portraitBorderColorA"
PORTRAIT_RESET_TARGETS[#PORTRAIT_RESET_TARGETS + 1] = "general.portraitBgColorA"
local ACTION_TARGETS = {
    reset_player_totems_layout = {
        "gameplay.playerTotemsIconSize",
        "gameplay.playerTotemsOffsetX",
        "gameplay.playerTotemsOffsetY",
        "gameplay.playerTotemsAnchorFrom",
        "gameplay.playerTotemsAnchorTo",
    },
    reset_focus_kick_position = {
        "general.focusKickIconOffsetX",
        "general.focusKickIconOffsetY",
    },
    enable_focus_target_frame = {
        "focus.enabled",
        "focustarget.enabled",
    },
    show_player_power_or_open_class_resources = {
        "player.showPowerBar",
    },
    reset_health_gradient_colors = {
        "general.healthGradient{stop}R",
        "general.healthGradient{stop}G",
        "general.healthGradient{stop}B",
    },
    reset_aura_colors = {
        "general.aurasCooldownTextUseBuckets", "general.aurasCooldownTextSafeColor", "general.aurasCooldownTextWarningColor",
        "general.aurasCooldownTextUrgentColor", "general.aurasCooldownTextSafeSeconds", "general.aurasCooldownTextWarningSeconds",
        "general.aurasCooldownTextUrgentSeconds", "general.dispelTypeColorOverrides",
    },
    reset_bar_background_color = {
        "general.classBarBgR",
        "general.classBarBgG",
        "general.classBarBgB",
        "general.classBarBgA",
    },
    reset_bar_colors = ColorTargets({ "general.absorbBarColor", "general.healAbsorbBarColor", "general.powerBarBgColor",
        "general.aggroBorder", "general.purgeBorderColor", "general.barOutlineColor" }, "RGBA",
        ColorTargets({ "general.healPredictionColor", "general.healthLossColor", "general.powerLossColor",
            "general.hlAggroColor", "general.hlPurgeColor", "general.aggroBorderColor" }, "RGB",
            { "general.barOutlineColorMode", "general.powerBarBgMatchBarColor" })),
    reset_castbar_colors = ColorTargets({ "general.castbarFont", "general.castbarTargetName", "general.castbarInterruptible",
        "general.castbarNonInterruptible", "general.castbarInterruptFeedback", "general.castbarInterruptUnavailable",
        "general.playerCastbarOverride" }, "RGB", ColorTargets({ "general.castbarBorder", "general.castbarBg" }, "RGBA",
            { "general.castbarInterruptUnavailableColor", "general.playerCastbarOverrideEnabled", "general.playerCastbarOverrideMode",
                "general.kickReadyColor", "general.kickNotReadyColor" })),
    reset_class_colors = {
        "classColors",
    },
    reset_global_font_color = {
        "general.useCustomFontColor",
        "general.fontColorCustomR",
        "general.fontColorCustomG",
        "general.fontColorCustomB",
    },
    reset_gameplay_colors = {
        "gameplay.combatTimerColor",
        "gameplay.combatStateEnterColor",
        "gameplay.combatStateLeaveColor",
        "gameplay.crosshairInRangeColor",
        "gameplay.crosshairOutRangeColor",
    },
    reset_npc_type_colors = {
        "npcColors",
    },
    reset_unitframe_colors = { "npcColors", "general.tapDeniedGray", "general.petFrameColorR", "general.petFrameColorG",
        "general.petFrameColorB", "general.petFrameUsePlayerClassColor", "general.npcClassColorBar" },
    reset_portrait_colors = PORTRAIT_RESET_TARGETS,
    reset_power_color_token = {
        "general.powerColorOverrides.{token}",
    },
    reset_class_power_color_token = {
        "general.classPowerColorOverrides.{token}",
        "general.classPowerBgColorOverrides.{token}",
    },
    reset_class_power_slot_colors = {
        "general.classPowerColorOverrides.{token}",
    },
    reset_class_power_full_color = {
        "general.classPowerColorOverrides.{token}_FULL",
        "bars.classPowerFullColorEnabled.{token}",
    },
    switch_profile = {
        "MSUF_GlobalDB.char.{character}.activeProfile",
    },
    create_profile = {
        "MSUF_GlobalDB.profiles.{profile}",
    },
    copy_profile = {
        "MSUF_GlobalDB.profiles.{profile}",
    },
    reset_profile = {
        "MSUF_GlobalDB.profiles.{profile}",
    },
    import_profile_string = {
        "MSUF_GlobalDB.profiles.{profile}",
    },
    delete_profile = {
        "MSUF_GlobalDB",
    },
    set_new_character_profile = {
        "MSUF_GlobalDB.global.defaultProfileForNewChars",
    },
    menu_history_undo = {
        "MSUF_DB",
    },
    menu_history_redo = {
        "MSUF_DB",
    },
    menu_reset_current_page_prompt = {
        "MSUF_DB",
    },
    menu_window_maximize = {
        "general.msuf2WindowW",
        "general.msuf2WindowH",
    },
    menu_window_restore = {
        "general.msuf2WindowW",
        "general.msuf2WindowH",
    },
    set_nav_search_intro = {
        "MSUF_GlobalDB.char.{character}.menu2State.searchIntroSeen",
    },
}
local NO_PROFILE_WRITE_ACTIONS = {
    open_page = true, export_profile = true, copy_wago_profiles_link = true,
    menu_search_clear = true, menu_window_close = true, menu_window_minimize = true,
    dashboard_page_back = true, dashboard_page_forward = true,
    ["menu.action.editMode.toggle"] = true, ["menu.action.editMode.enter"] = true,
}
local DASHBOARD_TARGETS = {
    ["display.recovery.factory.reset.all"] = { "MSUF_GlobalDB", "MSUF_DB" },
    ["display.recovery.reset.positions"] = { "MSUF_DB" },
    ["scaling.menu.apply"] = { "general.slashMenuScale" },
    ["scaling.msuf.frames.apply"] = { "general.msufUiScale" },
}
local function QuickSetupTargets()
    local paths = { "general.quickSetupClassBarOffered" }
    for root, fields in pairs(M.ClassPowerWorkspace.QuickWriteKeys) do
        for _, field in ipairs(fields) do paths[#paths + 1] = root .. "." .. field end
    end
    return Schema.Record(paths)
end
local function StatusResetTargets(group, scope)
    local specs = group and M.GroupPage.GF_STATUS_ICON_SPECS or M.UnitPage.STATUS_CONTROLS
    local roots = group and GROUP_SCOPE_ROOTS or { (scope:gsub("^uf_", "")) }
    local fields = group and { "size", "anchor", "x", "y", "layer", "iconStyle", "customIcon" }
        or { "x", "y", "anchor", "layer", "size", "symbol", "iconStyle", "customIcon", "width" }
    local names = group and { "levelTextDifficultyColor", "threatTextColorCurve", "threatTextBackground" }
        or { "raidGroupNameStyle", "levelIndicatorDifficultyColor", "levelIndicatorForeverBadge",
            "threatIndicatorColorCurve", "threatIndicatorBackground" }
    for _, selected in ipairs(specs) do
        for _, field in ipairs(fields) do
            if selected[field] then names[#names + 1] = selected[field] end
        end
        if not group and selected.colorPrefix then
            for _, channel in ipairs({ "R", "G", "B" }) do names[#names + 1] = selected.colorPrefix .. "Color" .. channel end
        end
    end
    return Schema.Fields(roots, names)
end
local function ActionDeclaration(spec, meta)
    local key, id = spec.actionKey or meta.actionKey, tostring(spec.id)
    local paths = ACTION_TARGETS[key]
    local dashboard = id:match("^menu2%.home%.dashboard%.(.+)$")
    if dashboard then
        paths = DASHBOARD_TARGETS[dashboard]
        if dashboard == "scaling.global.ui.apply" or dashboard:match("^scaling%.global%.ui%.preset%.") then
            paths = { "general.UIScale.Enabled", "general.UIScale.Scale",
                "general.globalUiScalePreset", "general.globalUiScaleValue" }
        elseif dashboard == "display.recovery.print.help" then
            spec.ephemeralReason = "Prints slash-command help; no profile setting is written."
        end
    end
    if key == "class_power_quick_setup" then return QuickSetupTargets() end
    if key == "reset_selected_group_status_icon" then return StatusResetTargets(true) end
    if key == "reset_unit_status_indicator" then return StatusResetTargets(false, spec.scope) end
    if key and key:match("^first_load%.") then paths = { "MSUF_GlobalDB.global.firstLoad6" } end
    if key == "reset_all_scoped_global_font_overrides" then return Schema.ScopedFields({ "fontOverride" }) end
    if key == "reset_all_scoped_global_bars_overrides" then
        return Schema.ScopedFields({ "hlOverride", "slantedBarDirection" }, nil, nil,
            { "hlOverride", "slantedBarDirection", "barTextureOverride" })
    end
    if key == "reset_bar_gradient_colors" then
        return Schema.ScopedFields({ "healthBarGradientColorR", "healthBarGradientColorG", "healthBarGradientColorB",
            "powerBarGradientColorR", "powerBarGradientColorG", "powerBarGradientColorB" }, "general", "hlOverride")
    end
    if id:match("^menu2%.gf_auras%.group%.spell%.tile%.slot%.%d+$") then
        paths = { "gf_party.spellIndicators", "gf_raid.spellIndicators", "gf_mythicraid.spellIndicators" }
    end
    if paths then return Schema.Record(paths) end
    if id:match("^menu2%.[^.]+%..*%.handle%..*%.open[_.]settings$")
        or id:match("^menu2%.menu%-chrome%.search%-shortcut%-") then
        spec.ephemeralReason = "Opens the named settings or search view; no profile setting is written."
    end
    if NO_PROFILE_WRITE_ACTIONS[key] or id:match("^menu2%.home%.dashboard%.support%.link%.")
        or id:match("^menu2%.home%.dashboard%.guided%.setup%.")
        or id:match("^advancedprofiles%.hero") or id == "section.actions" then
        spec.ephemeralReason = "Menu navigation, export or editor action; no profile setting is written."
    end
end

local function Declare(spec)
    local meta = spec.meta or {}
    spec.setting = spec.setting or meta.setting
    if not spec.setting and not spec.ephemeralReason and not meta.ephemeral and meta.classification ~= "ephemeral" then
        spec.setting = Schema.FromMeta(meta) or spec.settingPath
    else spec.setting = spec.setting or spec.settingPath end
    if spec.setting == "" then spec.setting = nil end
    if spec.id:match("^menu2%.home%.dashboard%.scaling%..+%.percent$") then
        spec.setting = nil
        spec.ephemeralReason = "Selects a pending scale percentage; only the separate Apply button writes the profile."
    elseif meta.schemaEphemeralReason then
        spec.setting, spec.ephemeralReason = nil, meta.schemaEphemeralReason
    elseif not spec.setting then spec.setting = ActionDeclaration(spec, meta) end
    if spec.setting then spec.ephemeralReason = nil end
    if not spec.setting and (meta.ephemeral or meta.classification == "ephemeral" or spec.applyDomain == "menuState"
        or spec.applyDomain == "sectionNavigation") then
        spec.ephemeralReason = spec.ephemeralReason or meta.ephemeralReason
            or "Menu selection, disclosure or preview state; no addon profile setting is written."
    end
    spec.writes = WriteContract(spec, not spec.setting and spec.ephemeralReason ~= nil)
    return spec
end
local function Metadata(spec)
    local meta = {}
    for key, value in pairs(spec.meta or {}) do meta[key] = value end
    meta.controlId = spec.id
    if spec.settingPath then meta.settingKey = spec.settingPath end
    if spec.help then meta.help = spec.help end
    if spec.keywords then meta.keywords = spec.keywords end
    if spec.roundStep then meta.step, meta.roundStep = spec.range[3], true end
    return meta
end
-- A single declaration owns the physical target. Families resolve the active
-- group at input time; selection-dependent families must provide their resolver.
function Schema.ResolvePath(spec)
    local setting = assert(spec.setting, "schema writer has no declared target: " .. spec.id)
    local resolve = spec.write and spec.write.resolve
    if resolve then
        local path = assert(resolve(), "schema write target resolver returned no path: " .. spec.id)
        assert(Schema.Matches(setting, path), "schema write target resolver escaped its family: " .. spec.id)
        return path
    end
    if type(setting) == "string" then return setting end
    if setting.resolve then
        local path = assert(setting.resolve(), "schema target resolver returned no path: " .. spec.id)
        assert(Schema.Matches(setting, path), "schema target resolver escaped its family: " .. spec.id)
        return path
    end
    local primary = spec.settingPath or (spec.meta and spec.meta.settingKey)
    if primary and Schema.Matches(setting, primary) then return primary end
    local paths = setting.keys or setting.recordPaths
    assert(paths and #paths > 0, "schema writer has no finite target: " .. spec.id)
    if #paths == 1 then return paths[1] end
    local root = spec.unit
    if spec.scope == "group" then root = "gf_" .. M.GroupPage.CurrentScope() end
    local result
    for _, path in ipairs(paths) do
        if root and path:sub(1, #root + 1) == root .. "." then
            assert(not result, "schema writer needs a selected-target resolver: " .. spec.id)
            result = path
        end
    end
    return assert(result, "schema writer target is ambiguous: " .. spec.id)
end
-- The accessor walks the complete declared path. A source callback only keeps
-- its existing record initialization; it cannot choose the destination record.
function Schema.ProfileRecord(spec, initialize)
    if initialize and spec.write.source then
        local initialized = spec.write.source()
        if not initialized and (spec.write.allowMissing or spec.write.requireRecord) then return nil end
    end
    local path = Schema.ResolvePath(spec)
    assert(not path:find("{", 1, true), "selected record needs a physical resolver: " .. spec.id)
    local record = M.EnsureDB()
    local parent = path:match("^(.*)%.[^.]+$") or ""
    for part in parent:gmatch("[^.]+") do
        local key = tonumber(part) or part
        if type(record[key]) ~= "table" then
            if not initialize then return nil end
            record[key] = {}
        end
        record = record[key]
    end
    return record
end
-- Section ownership decides which controls reset. Their destination is the
-- accessor's declaration; unopened sections retain the existing field policy.
local function RegisterResetTarget(widget, spec)
    local path = Schema.ResolvePath(spec)
    local root, key = path:match("^([^.]+)%.([^.]+)")
    if not root then return end
    local parent = widget:GetParent()
    while parent do
        local entry = parent._msuf2CollapsibleEntry
        if entry then
            local targets = entry._msuf2SchemaResetTargets
            if not targets then
                targets = {}
                entry._msuf2SchemaResetTargets = targets
            end
            targets[widget] = { spec = spec, root = root, key = key,
                nested = path:match("^[^.]+%.[^.]+%.") ~= nil }
            return
        end
        parent = parent:GetParent()
    end
end
function Schema.ResetSection(entry, keys, conf, defaults, factory, nested)
    local eligible, claimed = {}, {}
    for _, key in ipairs(keys) do eligible[key] = true end
    for _, target in pairs(entry._msuf2SchemaResetTargets or {}) do
        local root = target.root
        if target.spec.scope == "group" then root = "gf_" .. M.GroupPage.CurrentScope() end
        if (target.nested == true) == (nested == true) and eligible[target.key] and M.EnsureDB()[root] == conf then
            local path = Schema.ResolvePath(target.spec)
            local destination, field = Schema.ProfileRecord(target.spec, false), path:match("([^.]+)$")
            if destination then
                local source, defaultPath = factory, path
                local destinationRoot = path:match("^([^.]+)")
                if M.EnsureDB()[destinationRoot] == conf then
                    source, defaultPath = defaults, path:match("^[^.]+%.(.*)$")
                end
                for part in defaultPath:gmatch("[^.]+") do
                    if type(source) == "table" then source = source[tonumber(part) or part]
                    else source = nil end
                end
                destination[field] = M.DeepCopy(source)
                if not target.nested then claimed[target.key] = true end
            end
        end
    end
    return claimed
end
local function TargetParts(spec)
    local path = Schema.ResolvePath(spec)
    return path:match("^([^.]+)"), assert(path:match("([^.]+)$"), "schema field missing")
end
function Schema.Setter(spec)
    local write = assert(spec.write, "schema write policy missing")
    local args = write.args or {}
    return function(value)
        if write.accept and not write.accept(value) then return write.refused end
        local root, key = TargetParts(spec)
        if write.convert then value = write.convert(value) end
        if write.validNumber then
            value = tonumber(value)
            if value == nil then return false end
        end
        if write.boolean then value = value and true or false
        elseif write.strictBoolean then value = value == true
        elseif write.defaultSource then value = tonumber(value) or write.defaultSource()
        elseif write.numberDefault ~= nil then value = tonumber(value) or write.numberDefault
        elseif write.fallback ~= nil then value = value or write.fallback
        elseif spec.kind == "dropdown" and write.dropdownDefault ~= nil and not value then
            value = write.dropdownDefault
        end
        if write.clamp then value = math.max(spec.range[1], math.min(spec.range[2], value)) end
        if write.round then value = math.floor(value + 0.5) end
        if write.before then write.before(value) end
        local result
        if write.unitDomain then
            result = Schema.SetUnit(write.unitDomain, root, key, value, write.reason, spec.kind)
        elseif write.source then
            local record = Schema.ProfileRecord(spec, true)
            if not record and write.requireRecord then return end
            if write.skipEqual and record[key] == value then return end
            if write.call then result = write.call(record, key, value, unpack(args))
            elseif record or not write.allowMissing then record[key] = value end
        elseif write.valueOnly then result = write.call(value, unpack(args))
        elseif write.context then result = write.call(write.context, key, value, unpack(args))
        elseif write.keyOnly then result = write.call(key, value, unpack(args))
        else
            if write.group then root = root:match("^gf_(.+)$") end
            if write.parent then root = Schema.ResolvePath(spec):match("([^.]+)%.[^.]+$") end
            result = write.call(root, key, value, unpack(args))
        end
        if write.after then write.after(value) end
        if write.afterChanged and result then write.afterChanged(value) end
        if write.success then return true end
        if write.returns then return result end
    end
end
-- Existing readers retain their lazy defaults. The target is derived before a
-- default writer is built, so a stale row key cannot redirect a profile write.
local function UnitAccessors(spec)
    local owner = M.UnitPage
    local function Get()
        local unit, key = TargetParts(spec)
        if spec.kind == "toggle" then return owner.ReadBool(unit, key, spec.defaultSource()) end
        if spec.kind == "slider" then return owner.ReadNumber(unit, key, spec.defaultSource()) end
        return owner.GetConf(unit)[key] or spec.defaultSource()
    end
    spec.write = { unitDomain = spec.applyDomain, reason = spec.reason, after = spec.after } --[[schema setter: Schema.Unit]]
    return Get, Schema.Setter(spec)
end
local function Accessors(spec)
    if spec.write then return assert(spec.get, "schema writer getter missing"), Schema.Setter(spec) end
    if spec.set then return assert(spec.get, "schema custom getter missing"), spec.set end
    if spec.unit then return UnitAccessors(spec) end
    local source = assert(spec.source, "schema setting source missing")
    local function Get()
        local _, key = TargetParts(spec)
        source()
        local record = Schema.ProfileRecord(spec, false)
        local value = record and record[key]
        if value == nil then return spec.defaultSource() end
        if spec.kind == "slider" then return tonumber(value) or spec.defaultSource() end
        if spec.kind == "toggle" then return value and true or false end
        return value
    end
    spec.write = { call = M.AdvancedPage.SetValue, source = source, args = { spec.apply },
        dropdownDefault = spec.defaultSource(), returns = true } --[[schema setter: Schema.Source]]
    return spec.get or Get, Schema.Setter(spec)
end
function Schema.Bind(ctx, widget, spec)
    assert(type(spec.id) == "string" and spec.id ~= "", "schema stable control ID missing")
    assert(spec.scope and spec.applyDomain, "schema scope/apply domain missing")
    Declare(spec)
    local get, set = Accessors(spec)
    local meta = Metadata(spec)
    if spec.write then RegisterResetTarget(widget, spec) end
    widget._msuf2ControlSchema = spec
    if spec.workspace == "classpower" then
        local fallback = spec.defaultSource and spec.defaultSource()
        M.ClassPowerWorkspace.Bind(spec.kind, ctx, widget, get, set, fallback, meta)
    elseif spec.kind == "slider" then
        assert(spec.range and spec.defaultSource, "schema slider range/default source missing")
        M.BindNumberWidget(ctx, widget, get, set, spec.numberFallback or spec.defaultSource(), meta)
    elseif spec.kind == "toggle" then
        M.BindBoolWidget(ctx, widget, get, set, meta)
    elseif spec.kind == "dropdown" then
        M.BindDropdownWidget(ctx, widget, get, set, meta)
    elseif spec.kind == "segment" then
        M.BindSegment(ctx, widget, get, set, meta)
    elseif spec.kind == "textinput" then
        if spec.textAdapter then M.BindTextInputWidget(ctx, widget, get, set, spec.commitOnBlur, meta)
        else M.BindTextInput(ctx, widget, get, set, spec.commitOnBlur, meta) end
    elseif spec.kind == "color" then
        M.BindColor(ctx, widget, get, set, meta)
    else
        error("unsupported schema control kind: " .. tostring(spec.kind))
    end
    if spec.register then M.RegisterControlMetadata(widget, meta, spec.labelKey, spec.kind) end
    if spec.gate then
        M.TrackRefresh(ctx, function() W.SetControlEnabled(widget, spec.gate()) end)
    end
    PublishWrites(widget, spec)
    return widget
end
-- Custom composite widgets keep their existing binding owner (scope/copy/color
-- shortcuts). Their declaration documents the seam without binding them twice.
function Schema.Custom(widget, spec)
    assert(spec.id and spec.kind and spec.scope and spec.applyDomain, "custom schema row is incomplete")
    local command = spec.meta and spec.meta.command
    if command and command.write and command.write.virtual and not command.set then
        spec.get, spec.write = command.get, command.write
        Declare(spec)
        spec.set = Schema.Setter(spec)
        command.set = spec.set
    end
    widget._msuf2ControlSchema = Declare(spec)
    PublishWrites(widget, spec)
    return widget
end
-- Native Click dispatches the current owned button's scripts and separate hooks.
function Schema.ButtonAction(widget)
    return function(_, ...) return widget:Click(...) end
end
-- Composite chrome retains the exact registered owner, including navigation and
-- button scripts. Callers name the actual widget; no catalog scan manufactures rows.
function Schema.Owned(widget, scope, domain)
    local record = assert(widget._msuf2RuntimeControlRecord, "schema composite owner missing")
    local previous = widget._msuf2ControlSchema
    if previous and previous.id ~= record.controlId then previous = nil end
    local command = widget._msuf2CommandAction or record.command
    local spec = {
        id = record.controlId, kind = record.kind, labelKey = record.label,
        settingPath = record.settingKey, scope = scope, applyDomain = domain,
        meta = widget._msuf2SearchMeta, actionKey = record.actionKey,
        setting = (widget._msuf2ControlSchema and widget._msuf2ControlSchema.setting) or
            Schema.FromMeta(widget._msuf2SearchMeta),
        ephemeralReason = record.classification == "ephemeral" and
            "Menu selection, disclosure or preview state; no addon profile setting is written." or nil,
        get = command and command.get and function(...)
            return (widget._msuf2CommandAction or record.command).get(...)
        end,
        write = (previous and previous.write) or (command and command.write),
        writeTargets = previous and previous.writeTargets,
        companionWrites = previous and previous.companionWrites,
        customSetReason = previous and previous.customSetReason or "Dispatches the composite widget's existing command owner.",
        set = command and command.set and function(...)
            return (widget._msuf2CommandAction or record.command).set(...)
        end,
        values = widget.GetValues and function() return widget:GetValues() end,
        action = widget.GetScript and widget:GetScript("OnClick") and Schema.ButtonAction(widget), owner = widget,
    }
    if command and command.write then
        Declare(spec)
        local set = Schema.Setter(spec)
        command.set = function(...)
            if M.BlockCombatAction() then return false end
            return set(...)
        end
    end
    return Schema.Custom(widget, spec)
end
function Schema.Section(section, scope)
    local header = assert(section._msuf2CollapsibleEntry).header
    Schema.Owned(header, scope, "sectionNavigation")
    local id = header._msuf2RuntimeControlRecord.controlId .. ".colors"
    Schema.ContextColors(section, id, scope)
    Schema.ContextColors(header, id, scope)
    return section
end
-- Opt in at the pilot's existing card/section owner. The shortcut keeps its
-- installed click wrapper, current options and relevance callback; it stays
-- noSearch and never gains a second command or input/history binding.
function Schema.ContextColors(card, id, scope)
    local function Declare(widget)
        Schema.Custom(widget, {
            id = id, kind = "button", labelKey = widget._msuf2Label:GetText(),
            scope = scope, applyDomain = "contextColors", owner = widget,
            ephemeralReason = "Opens the contextual color editor; this button does not write a profile setting.",
            get = function() return widget._msuf2ContextColorOptions end,
            action = Schema.ButtonAction(widget), gate = widget._msuf2RefreshContextColorVisibility,
        })
    end
    card._msuf2DeclareContextColorShortcut = Declare
    if card._msuf2ContextColorShortcut then Declare(card._msuf2ContextColorShortcut) end
    return card
end
function Schema.Render(ctx, parent, spec, layout)
    if spec.wanted and not spec.wanted() then return nil end
    layout = layout or spec.layout or {}
    local width = layout.width or 280
    local label = spec.labelKey
    local widget
    if spec.kind == "slider" then
        local range = spec.range
        widget = W.Slider(parent, label, range[1], range[2], range[3], width)
        if spec.percent then M.UsePercentInput(widget) end
    elseif spec.kind == "toggle" then
        if spec.view == "header" then widget = W.SectionSwitch(parent, label)
        elseif spec.view == "switch" then widget = W.SwitchAt(parent, label, layout.x, layout.y, width)
        elseif spec.view == "at" then widget = W.ToggleAt(parent, label, layout.x, layout.y, width)
        else widget = W.Toggle(parent, label) end
    elseif spec.kind == "dropdown" then widget = W.Dropdown(parent, label, spec.values, width)
    elseif spec.kind == "segment" then widget = W.Segment(parent, label, spec.values, width)
    elseif spec.kind == "textinput" then widget = W.TextInput(parent, label, width, spec.translatedLabel)
    else error("schema custom widget must be supplied to Bind") end
    if spec.beforeBind then spec.beforeBind(widget) end
    Schema.Bind(ctx, widget, spec)
    -- Toggles created at a position are already placed.
    if layout.x and not (spec.kind == "toggle" and (spec.view == "switch" or spec.view == "at")) then
        W.MoveWidget(widget, parent, layout.x, layout.y, layout.moveWidth, layout.align)
    end
    return widget
end
function Schema.Flow(ctx, parent, rows, layout)
    local controls = {}
    for i, spec in ipairs(rows) do
        local column = (i - 1) % layout.columns
        local row = math.floor((i - 1) / layout.columns)
        controls[spec.key or spec.id] = Schema.Render(ctx, parent, spec, {
            width = layout.width, x = layout.x + column * (layout.width + layout.gap),
            y = layout.y - row * layout.rowHeight,
            moveWidth = layout.moveWidth or (spec.kind == "toggle" and layout.width - 36 or layout.width),
            align = layout.align,
        })
    end
    return controls
end

-- Replacing rows hold kind, key, UI default, native constructor arguments and
-- optional placement arguments.
local ROW_CREATORS = {
    switch = "SwitchAt", toggle = "ToggleAt",
    slider = "Slider", dropdown = "Dropdown",
    textinput = "TextInput", color = "Color",
    sectionSwitch = "SectionSwitch", segment = "Segment", flowToggle = "Toggle",
    text = "Text", topButton = "TopButton", roleButton = "RoleButton",
}
local ROW_KINDS = { switch = "toggle", toggle = "toggle",
    slider = "slider", dropdown = "dropdown", textinput = "textinput", color = "color",
    sectionSwitch = "toggle", flowToggle = "toggle", segment = "segment" }
local ROW_CHROME = { text = "text", font = "font", card = "card",
    scopebar = "segment", topButton = "button", roleButton = "button" }
local function PlaceRow(widget, parent, row)
    local p = row[5]
    if not p then return end
    W.MoveWidget(widget, parent, p[1], p[2], p[3], p[4])
end
local function RowFlags(widget, flags)
    if not flags then return end
    for key, value in pairs(flags) do widget[key] = value end
end
-- Composite rows call the native owner once; a scope bar must never receive
-- a second segment binding. Cards declare existing and later-attached shortcuts.
local function CreateCompositeRow(ctx, parent, row)
    local kind, args = row[1], row[4]
    if kind == "font" then return M.Theme.Font(parent, unpack(args)) end
    if kind == "scopebar" then return W.ScopeOverrideBar(ctx, parent, args[1]) end
    if kind == "card" then
        return W.ControlCard(parent, args[1], args[2], args[3], args[4], args[5], args[6], args[7])
    end
    error("unsupported replacing row")
end
-- The same native scope selector may be built by a page-owned composite.
function Schema.ScopeOwner(widget, scope, domain, writeTargets)
    Schema.Owned(widget, scope, domain or "menuState")
    local spec = widget._msuf2ControlSchema
    spec.get = function() return widget:GetValue() end
    spec.customSetReason = "Changes the scope selector's editor state through its native widget."
    spec.set = function(value) return widget:SetValue(value) end
    spec.values = widget.values
    if writeTargets then
        spec.writeTargets = writeTargets
        spec.writes = WriteContract(spec, false)
        PublishWrites(widget, spec)
    end
    return widget
end
local function DeclareRow(ctx, widget, row, kind)
    local scope = row.scope or (ctx and ctx.key) or "shared"
    if row[1] == "scopebar" then
        Schema.ScopeOwner(widget, scope, row.domain, row.writeTargets)
        return
    end
    local meta = row.meta
    local id = meta and meta.controlId or row[2]
    Schema.Custom(widget, { id = id, kind = kind,
        labelKey = row[1] == "font" and row[4][2] or row[4][1], meta = meta,
        scope = scope, applyDomain = row.domain or "presentation", owner = widget,
        action = kind == "button" and Schema.ButtonAction(widget) or nil })
    if kind == "card" then Schema.ContextColors(widget, id .. ".colors", scope) end
end
-- The UnitSections typed policy, shared without changing its native binders.
function Schema.UnitBinding(ctx, widget, row, kind)
    if row.bind then
        row.bind(widget)
        if widget._msuf2ControlSchema then
            M.ControlSchema.SetSetting(widget, row.setting or widget._msuf2ControlSchema.setting)
            return widget
        end
        return Schema.Custom(widget, { id = row[2], kind = kind, labelKey = row[4][1],
            scope = row.scope or "shared", applyDomain = "menuState", owner = widget, setting = row.setting })
    end
    local meta = assert(row.meta, "unit row metadata missing")
    local spec = { id = meta.controlId, kind = kind, key = row[2], labelKey = row[4][1],
        meta = meta, scope = row.scope or ctx.key, applyDomain = row.domain or "unit",
        writeTargets = row.writeTargets,
            companionWrites = row.companionWrites,
        settingPath = meta.settingKey, setting = row.setting, get = row.get, set = row.set, write = row.write,
            customSetReason = row.customSetReason, unit = row.unit,
        reason = row.reason, commitOnBlur = row.commitOnBlur, textAdapter = row.textAdapter,
        defaultSource = function() return row[3] end, roundStep = row.roundStep }
    if kind == "slider" then spec.range = { row[4][2], row[4][3], row[4][4] } end
    return Schema.Bind(ctx, widget, spec)
end
function Schema.UnitOptions()
    return { bind = Schema.UnitBinding }
end
function Schema.Build(ctx, parent, rows, opts, refs)
    opts, refs = opts or {}, refs or {}
    for _, row in ipairs(rows) do
        local widget, args, rowParent = nil, row[4], row.parent or parent
        if row[1] == "button" then widget = M.Theme.Button(rowParent, unpack(args))
        elseif ROW_CREATORS[row[1]] then widget = W[ROW_CREATORS[row[1]]](rowParent, unpack(args))
        else widget = CreateCompositeRow(ctx, rowParent, row) end
        refs[row[2]] = widget
        if row.anchor then widget:SetPoint(unpack(row.anchor)) end
        if row.center then M.Theme.CenterButtonLabel(widget) end
        RowFlags(widget, row.flagsBefore)
        if opts.beforeBind then opts.beforeBind(widget, row) end
        if row.beforeBind then row.beforeBind(widget, row) end
        if ROW_KINDS[row[1]] then opts.bind(ctx, widget, row, ROW_KINDS[row[1]]) end
        RowFlags(widget, row.flagsAfter)
        if row.tip and M.AddTooltip then M.AddTooltip(widget, unpack(row.tip)) end
        if row.action then widget:SetScript("OnClick", row.action) end
        if row.register then assert(opts.register, "schema row registry missing")(ctx, widget, row) end
        if ROW_CHROME[row[1]] then DeclareRow(ctx, widget, row, ROW_CHROME[row[1]]) end
        PlaceRow(widget, rowParent, row)
    end
    return refs
end

-- Shared column arithmetic keeps each page's existing inset, ratio and caps.
function Schema.Columns(parent, width, inset, gap, ratio, leftLow, leftHigh, rightLow, rightHigh)
    width = parent._msuf2Width or width or 720
    local inner = math.max(320, width - inset * 2)
    local left = math.floor((inner - gap) * ratio)
    if leftLow then left = math.max(leftLow, math.min(leftHigh, left)) end
    local right = inner - left - gap
    if rightLow then right = math.max(rightLow, math.min(rightHigh, right)) end
    return inset, left, inset + left + gap, right, inner, width
end

-- Named color options retain the exact existing shortcut/reference owner.
function Schema.Colors(parent, references, opts)
    local create = references and W.AttachContextColorReferences or W.AttachContextColorShortcut
    if not create then return end
    if references then return create(parent, references, opts) end
    return create(parent, opts)
end

-- Group scope resolves at input time. The existing group and central bindings
-- retain sole ownership of history, combat refusal, rounding and apply requests.
function Schema.GroupBinding(ctx, widget, row, kind)
    local gp = M.GroupPage
    local key, default, domain = row[2], row[3], row.domain or "visual"
    local meta = row.meta or gp.ControlMeta(ctx, row.path or "field." .. tostring(key), row.classification)
    local spec = { id = meta.controlId, kind = kind, key = key, labelKey = row[4][1],
        scope = "group", applyDomain = domain, meta = meta, setting = row.setting or Schema.GroupKeys(key),
        defaultSource = function() return default end }
    if kind == "slider" then
        spec.range, spec.numberFallback = { row[4][2], row[4][3], row[4][4] }, default
        meta.step, meta.roundStep = 1, true
    end
    local read = kind == "toggle" and gp.Bool or kind == "slider" and gp.Num or gp.Val
    spec.get = function()
        local root, field = TargetParts(spec)
        return read(root:match("^gf_(.+)$"), field, default)
    end
    spec.write = { call = gp.Set, group = true, args = { domain }, boolean = kind == "toggle",
        numberDefault = kind == "slider" and (default or 0) or nil, round = kind == "slider",
        fallback = kind == "dropdown" and default or nil,
        after = kind == "toggle" and function() gp.RefreshContext(ctx) end or nil } --[[schema setter: Schema.Group]]
    if kind == "dropdown" then spec.write.fallback = default end
    return Schema.Bind(ctx, widget, spec)
end

-- Record rows retain the selected scope and nested-record owners at input time.
-- A missing record differs from a missing toggle field; false subtypes disable it.
local function CommandAccessors(owner, row, kind, widget, ctx)
    if row.set or row.write then return assert(row.get, "command row getter missing"), row.set, row[3] end
    local command = row.lifecycle and row.lifecycle(widget, ctx, row) or owner.commands[row[2]]
    local fallback = command.default
    if fallback == nil then fallback = row[3] end
    row.write, row.customSetReason = command.write, command.customSetReason
    row.writeTargets, row.companionWrites = command.writeTargets, command.companionWrites
    return command.get, command.set, fallback, command.afterBind
end
local function RecordAccessors(owner, row, kind, widget, ctx, spec)
    if row.lifecycle then return CommandAccessors(owner, row, kind, widget, ctx) end
    if row.set or row.write then return assert(row.get, "record row getter missing"), row.set, row[3] end
    local config, scope, key, default = row.source or owner.config, owner.scope, row[2], row[3]
    local function Get()
        local record = config(scope(), false)
        if kind == "color" then
            local fields = row.channels
            return (record and record[fields[1]]) or default[1],
                (record and record[fields[2]]) or default[2], (record and record[fields[3]]) or default[3]
        end
        local value = record and record[key]
        if row.subtype then return type(value) == "table" and value.type or "none" end
        if kind == "toggle" then
            if not record then return false end
            if value == nil then return default and true or false end
            if owner.strictToggles then return value == true end
            return value and true or false
        end
        if kind == "slider" then return tonumber(value) or default end
        return value or default
    end
    if not row.accept and kind ~= "color" and not row.subtype and not row.convert
        and not owner.recordPath:find("{", 1, true)
        and not row.uncheckedNil and not row.afterWrite then
        row.write = { source = function() return config(scope(), true) end,
            allowMissing = not row.requireRecord, requireRecord = row.requireRecord,
            boolean = kind == "toggle" and not owner.strictToggles,
            strictBoolean = kind == "toggle" and owner.strictToggles,
            numberDefault = kind == "slider" and default or nil, round = kind == "slider" and not owner.rawNumber,
            fallback = kind ~= "toggle" and kind ~= "slider" and default or nil,
            after = function()
                owner.changed(scope())
                local afterSet = row.afterSet or (kind == "toggle" and owner.afterToggle)
                if afterSet then afterSet() end
            end } --[[schema setter: Schema.Record]]
        if kind ~= "toggle" and kind ~= "slider" then row.write.fallback = default end
        return row.get or Get, nil, row[3]
    end
    row.customSetReason = row.customSetReason or "Edits a composite record with conversion, subtype defaults or dependent channels."
    local function Set(value, green, blue)
        if row.accept and not row.accept(value) then return end
        local record = config(scope(), true)
        if kind == "color" then
            if record then record[row.channels[1]], record[row.channels[2]], record[row.channels[3]] = value, green, blue end
        elseif row.subtype then
            if not record then return end
            if value == "none" then record[key] = false
            else
                record[key] = type(record[key]) == "table" and record[key] or {}
                record[key].type = value
                if row.defaults then row.defaults(record[key]) end
            end
        elseif not record and row.requireRecord then return
        elseif record then
            if row.convert then
                local converted = row.convert(value)
                record[key] = converted
                if row.afterWrite then row.afterWrite(record, converted) end
            elseif kind == "toggle" then
                if row.uncheckedNil then record[key] = value and true or nil
                elseif owner.strictToggles then record[key] = value == true
                else record[key] = value and true or false end
            elseif kind == "slider" then
                local number = tonumber(value) or default
                record[key] = owner.rawNumber and number or math.floor(number + 0.5)
            else record[key] = value or default end
        end
        owner.changed(scope())
        local afterSet = row.afterSet or (kind == "toggle" and owner.afterToggle)
        if afterSet then afterSet() end
    end
    return row.get or Get, Set, row[3]
end
local function GroupBindingOptions(owner, accessors)
    return { bind = function(ctx, widget, row, kind)
        if row.bind then
            row.bind(ctx, widget, row)
            Schema.Owned(widget, "group", row.domain or "visual")
            M.ControlSchema.SetSetting(widget, row.setting or widget._msuf2ControlSchema.setting)
            return
        end
        local get, set, fallback, afterBind = accessors(owner, row, kind, widget, ctx)
        local path = row.path or owner.path .. tostring(row[2])
        if row.identitySuffix then path = path .. "." .. row.identitySuffix end
        local meta = kind == "slider" and owner.stepMeta(ctx, path, row[4][4]) or owner.meta(ctx, path, row.classification)
        local spec = { id = meta.controlId, kind = kind, key = row[2], labelKey = row[4][1],
            scope = "group", applyDomain = row.domain or "visual", meta = meta, get = get, set = set,
            write = row.write, customSetReason = row.customSetReason,
            writeTargets = row.writeTargets,
            companionWrites = row.companionWrites or owner.companionWrites,
            commitOnBlur = row.commitOnBlur, setting = row.setting or (owner.setting and owner.setting(row)) }
        if kind == "slider" then
            spec.range, spec.defaultSource = { row[4][2], row[4][3], row[4][4] }, function() return fallback end
        end
        Schema.Bind(ctx, widget, spec)
        if afterBind then afterBind() end
        local command = widget._msuf2CommandAction
        spec.get, spec.set = command and command.get, command and command.set
    end }
end

function Schema.GroupRecordOptions(owner)
    owner.setting = function(row)
        local prefix = "gf_{scope}." .. assert(owner.recordPath, "group record path missing")
        local paths = {}
        for _, field in ipairs(row.channels or { row[2] }) do paths[#paths + 1] = prefix .. field end
        local setting = Schema.Record(paths)
        if #paths == 1 then
            setting.resolve = function() return paths[1]:gsub("{scope}", owner.scope()) end
        end
        return setting
    end
    return GroupBindingOptions(owner, RecordAccessors)
end

-- Selected-field rows use the existing scope readers and writes. The selected
-- provider and callable default are resolved anew for every read and input.
local function SelectedAccessors(owner, row, kind)
    row.customSetReason = row.customSetReason or "Resolves the selected status-icon field and its per-record default at input time."
    local selected, scope, default = owner.selected, owner.scope, owner.default
    local field, valueDefault, domain = row[2], row[3], row.domain or "visual"
    local low, high = row[4][2], row[4][3]
    local reader = kind == "toggle" and owner.bool or owner.number
    local fallback
    if kind == "slider" then fallback = default(selected(), valueDefault) end
    local function Get()
        local spec = selected()
        if kind == "dropdown" then
            local key = spec and spec[field]
            return key and owner.value(scope(), key, default(spec, valueDefault)) or default(spec, valueDefault)
        end
        local value = reader(scope(), spec[field], default(spec, valueDefault))
        if row.clamp then
            if value < low then value = low elseif value > high then value = high end
        end
        return value
    end
    local function Set(value)
        local spec = selected()
        if kind == "dropdown" then
            local key = spec and spec[field]
            if not key then return end
            owner.write(scope(), key, value or default(spec, valueDefault), domain)
        else
            if kind == "toggle" then value = value and true or false
            else value = math.floor((tonumber(value) or default(spec, valueDefault)) + 0.5) end
            if row.clamp then
                if value < low then value = low elseif value > high then value = high end
            end
            owner.write(scope(), spec[field], value, domain)
        end
        if row.afterSet then row.afterSet() end
    end
    return row.get or Get, Set, fallback
end
function Schema.GroupSelectedOptions(owner)
    owner.setting = function(row)
        local keys = {}
        for _, selected in ipairs(owner.specs) do
            local field = selected[row[2]]
            if field then
                for _, path in ipairs(Schema.GroupKeys(field).keys) do keys[#keys + 1] = path end
            end
        end
        return Schema.Family(keys, function()
            local selected = owner.selected()
            local field = selected and selected[row[2]]
            return field and "gf_" .. owner.scope() .. "." .. field
        end)
    end
    return GroupBindingOptions(owner, SelectedAccessors)
end

-- Typed policies supply business operations; central Bind retains input/history/combat ownership.
function Schema.GroupCommands(commands, meta, stepMeta)
    return GroupBindingOptions({ commands = commands, path = "", meta = meta, stepMeta = stepMeta }, CommandAccessors)
end
local function ScopeMeta(ctx, path, step)
    local meta = M.GroupPage.ControlMeta(ctx, path, type(step) == "string" and step or nil)
    if type(step) == "number" then meta.step, meta.roundStep = step, true end
    return meta
end
local function ScopeAccessors(owner, row, kind)
    local gp, key, default = M.GroupPage, row[2], row[3]
    local function Target()
        if row.target then return row.target() end
        return key, default
    end
    local function Get()
        local field, fallback = Target()
        local value = (kind == "slider" and gp.Num or gp.Val)(gp.CurrentScope(), field, fallback)
        if row.scale then return math.floor(value * row.scale + 0.5) end
        return value
    end
    if not row.target and not row.scale and not row.select then
        local fallback = row.writeDefault
        if fallback == nil then fallback = default end
        row.write = { call = gp.Set, group = true, args = { row.domain or "visual" },
            fallback = fallback, after = row.afterSet } --[[schema setter: Schema.Scope]]
        return Get, nil, row.fallback or default
    end
    row.customSetReason = "Resolves a selected field, applies a scale conversion or updates editor selection."
    local function Set(value)
        local field = Target()
        if row.select then M.SetMenuStateValue(row.select[1], row.select[2]) end
        if row.scale then value = (tonumber(value) or row.fallback) / row.scale
        else
            local fallback = row.writeDefault
            if fallback == nil then fallback = default end
            value = value or fallback
        end
        gp.Set(gp.CurrentScope(), field, value, row.domain or "visual")
        if row.afterSet then row.afterSet() end
    end
    return Get, Set, row.fallback or default
end
local SCOPE_OPTIONS = GroupBindingOptions({ path = "field.", meta = ScopeMeta, stepMeta = ScopeMeta }, ScopeAccessors)
function Schema.GroupOptions()
    return { bind = function(ctx, widget, row, kind)
        if row.binding == "scopeValue" then
            row.setting = row.setting or Schema.GroupKeys(row.target and row.target() or row[2])
            SCOPE_OPTIONS.bind(ctx, widget, row, kind)
        else Schema.GroupBinding(ctx, widget, row, kind) end
    end }
end
function Schema.GroupNestedBinding(ctx, widget, row)
    M.GroupPage.BindNestedSlider(ctx, widget, row.source, row[2], row[3], row.domain or "visual", row.path)
end
