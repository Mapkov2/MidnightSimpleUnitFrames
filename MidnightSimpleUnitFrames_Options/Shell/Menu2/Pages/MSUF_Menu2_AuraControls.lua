-- Shared Aura controls and apply scheduling; no dependency on a page builder.
local _, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_AuraControls.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W, T = M.Widgets, M.Theme
local VTP = M.ValueTextPairs
local C_Timer = M.MenuTimer or C_Timer
local CreateFrame = CreateFrame
-- Resolved once: slider writes request the aura runtime on every tick.
local ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
local floor, max, min = math.floor, math.max, math.min
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local AurasMenuCombatLocked = M.AuraSettings.AurasMenuCombatLocked
local CurrentLane = M.AuraSettings.CurrentLane
local Round = M.AuraSettings.Round
local SetCurrentLane = M.AuraSettings.SetCurrentLane

local LANE_VALUES = VTP "buff=Buffs|debuff=Debuffs"

local AuraCatalogToken = M.AuraCatalogToken

local function AuraCatalogPageKey(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "auras")
end

local function ConfigureSearchView(ctx, kind, value)
    ctx._auraSearchKind, ctx._auraSearchValue = kind, value
    ctx._auraSearchPrepare = function(_, target)
        return target.prepareKind == kind and target.prepareValue == value
    end
end
local function AttachSearchView(ctx, meta)
    if ctx and ctx._auraSearchKind then
        meta.sectionId = "auras"
        meta.searchPrepareKind, meta.searchPrepareValue = ctx._auraSearchKind, ctx._auraSearchValue
        meta.prepareExactSearchTarget = ctx._auraSearchPrepare
    end
    return meta
end
-- Per-control storage contracts. Selector aliases route search; these narrow
-- fields describe each writer independently of the container currently selected.
local CUSTOM_SETTING_FIELDS = {
    ["appearance.cooldown-anchor"] = "placed.cooldownAnchor",
    ["appearance.cooldown-swipe"] = "placed.showCooldownSwipe",
    ["appearance.cooldown-text"] = "placed.showCooldown",
    ["appearance.cooldowndecimalseconds"] = "placed.cooldownDecimalSeconds",
    ["appearance.cooldownsize"] = "placed.cooldownSize",
    ["appearance.cooldownx"] = "placed.cooldownX",
    ["appearance.cooldowny"] = "placed.cooldownY",
    ["appearance.dispel-type-border"] = "placed.debuffTypeBorderMode",
    ["appearance.duration-bar"] = "placed.showDurationBar",
    ["appearance.duration-direction"] = "placed.durationBarDirection",
    ["appearance.duration-display"] = "placed.durationBarDisplay",
    ["appearance.duration-position"] = "placed.durationBarPosition",
    ["appearance.durationbarheight"] = "placed.durationBarHeight",
    ["appearance.icon-zoom"] = "placed.iconZoom",
    ["appearance.opacity"] = "placed.alpha",
    ["appearance.pandemic.blend"] = "placed.pandemicBlend",
    ["appearance.pandemic.border-opacity"] = "placed.pandemicBorderAlpha",
    ["appearance.pandemic.color"] = "placed.pandemicColor",
    ["appearance.pandemic.enabled"] = "placed.pandemicEnabled",
    ["appearance.pandemic.style"] = "placed.pandemicStyle",
    ["appearance.pandemic.tint-opacity"] = "placed.pandemicTintAlpha",
    ["appearance.pandemicpadding"] = "placed.pandemicPadding",
    ["appearance.pandemicthickness"] = "placed.pandemicThickness",
    ["appearance.stack-anchor"] = "placed.stackAnchor",
    ["appearance.stack-count"] = "placed.showStacks",
    ["appearance.stacksize"] = "placed.stackSize",
    ["appearance.stackx"] = "placed.stackX",
    ["appearance.stacky"] = "placed.stackY",
    ["appearance.style-padding"] = "placed.stylePadding",
    ["appearance.swipe-direction"] = "placed.cooldownSwipeReverse",
    ["appearance.tooltip"] = "placed.showTooltip",
    ["effect.color"] = "frame.color",
    ["effect.layer"] = "frame.layer",
    ["effect.only-during-pandemic-window"] = "frame.onlyInPandemicWindow",
    ["effect.opacity"] = "frame.color",
    ["effect.priority"] = "frame.priority",
    ["effect.thickness"] = "frame.thickness",
    ["effect.type"] = "frame.type",
    ["filters.bigdefensive"] = "filters.bigDefensive",
    ["filters.cancelable"] = "filters.cancelable",
    ["filters.crowdcontrol"] = "filters.crowdControl",
    ["filters.dispellableany"] = "filters.dispellableAny",
    ["filters.enabled"] = "filters.enabled",
    ["filters.externaldefensive"] = "filters.externalDefensive",
    ["filters.hide-permanent"] = "filters.hidePermanent",
    ["filters.hidepermanent"] = "filters.hidePermanent",
    ["filters.includedispellable"] = "filters.includeDispellable",
    ["filters.includenameplateonly"] = "filters.includeNameplateOnly",
    ["filters.max-duration"] = "filters.maxDuration",
    ["filters.maxduration"] = "filters.maxDuration",
    ["filters.notcancelable"] = "filters.notCancelable",
    ["filters.onlyimportant"] = "filters.onlyImportant",
    ["filters.onlymine"] = "filters.onlyMine",
    ["filters.raid"] = "filters.raid",
    ["filters.raidincombat"] = "filters.raidInCombat",
    ["layout.anchor"] = "placed.anchor",
    ["layout.growth"] = "placed.growth",
    ["layout.layer"] = "layer",
    ["layout.max"] = "placed.max",
    ["layout.perrow"] = "placed.perRow",
    ["layout.size"] = "placed.size",
    ["layout.spacing"] = "placed.spacing",
    ["reminder.click-cast"] = "placed.reminderClickCast",
    ["reminder.color"] = "placed.reminderColor",
    ["reminder.desaturate"] = "placed.reminderDesaturate",
    ["reminder.enabled"] = "placed.reminderEnabled",
    ["reminder.enchant-duration"] = "reminderEnchantDurationMinutes",
    ["reminder.enchant-main-hand"] = "reminderEnchantMainHand",
    ["reminder.enchant-off-hand"] = "reminderEnchantOffHand",
    ["reminder.only-castable"] = "placed.reminderOnlyCastable",
    ["reminder.opacity"] = "placed.reminderAlpha",
    ["setup.aura-type"] = "auraType",
    ["setup.enabled"] = "enabled",
    ["setup.name"] = "name",
}
local STYLE_SETTING_FIELDS = {
    ["anchor"] = "anchor",
    ["auras3-cooldown-anchor"] = "cooldownTextAnchor",
    ["auras3-cooldown-swipe-direction"] = "cooldownSwipeReverse",
    ["auras3-debuff-type-border-mode"] = "debuffTypeBorderMode",
    ["auras3-duration-bar-direction"] = "durationBarDirection",
    ["auras3-duration-bar-display"] = "durationBarDisplay",
    ["auras3-duration-bar-position"] = "durationBarPosition",
    ["auras3-stealable-marker-style"] = "stealableStyle",
    ["auras3-sort-method"] = "sortMethod", ["auras3-sort-direction"] = "sortReverse",
    ["hide-permanent"] = "blacklist.hidePermanent",
    ["cooldown-swipe-direction"] = "cooldownSwipeReverse",
    ["cooldownanchor"] = "cooldownAnchor",
    ["cooldowndecimalseconds"] = "cooldownDecimalSeconds",
    ["cooldownsize"] = "cooldownSize",
    ["cooldowntextoffsetx"] = "cooldownTextOffsetX",
    ["cooldowntextoffsety"] = "cooldownTextOffsetY",
    ["cooldowntextsize"] = "cooldownTextSize",
    ["cooldownx"] = "cooldownX",
    ["cooldowny"] = "cooldownY",
    ["dispel-border-mode"] = "dispelBorderMode",
    ["durationbardirection"] = "durationBarDirection",
    ["durationbardisplay"] = "durationBarDisplay",
    ["durationbarheight"] = "durationBarHeight",
    ["durationbarposition"] = "durationBarPosition",
    ["dynamicscale"] = "dynamicScale",
    ["growth"] = "growth",
    ["icon-height"] = "height",
    ["icon-size"] = "size",
    ["iconzoom"] = "iconZoom",
    ["layer"] = "layer",
    ["max"] = "max",
    ["max-duration"] = "maxDuration",
    ["max-icons"] = "max",
    ["per-row"] = "perRow",
    ["perrow"] = "perRow",
    ["showcooldown"] = "showCooldown",
    ["showcooldownswipe"] = "showCooldownSwipe",
    ["showcooldowntext"] = "showCooldownText",
    ["showdurationbar"] = "showDurationBar",
    ["showstackcount"] = "showStackCount",
    ["showstacks"] = "showStacks",
    ["showstealable"] = "showStealable",
    ["showtooltip"] = "showTooltip",
    ["size"] = "size",
    ["spacing"] = "spacing",
    ["stack-anchor"] = "stackCountAnchor",
    ["stackanchor"] = "stackAnchor",
    ["stacksize"] = "stackSize",
    ["stacktextoffsetx"] = "stackTextOffsetX",
    ["stacktextoffsety"] = "stackTextOffsetY",
    ["stacktextsize"] = "stackTextSize",
    ["stackx"] = "stackX",
    ["stacky"] = "stackY",
    ["stylepadding"] = "stylePadding",
}

-- Physical profile targets are separate from the stable search/navigation aliases.
local function UnitLayoutSetting(unit, fields)
    local schema, keys = MSUF.MSUF_Auras3.LaneKeySchema, {}
    if unit == "shared" then return M.ControlSchema.Fields({ "auras3.shared" }, fields) end
    for _, runtimeUnit in ipairs(schema.UNIT_FAMILIES[unit] or { unit }) do
        local root = "auras3.perUnit." .. runtimeUnit .. "."
        for _, field in ipairs(fields) do
            local shared = schema.SHARED_LAYOUT_KEYS[field]
            keys[#keys + 1] = root .. (shared and "layoutShared." or "layout.") .. field
            keys[#keys + 1] = root .. (shared and "overrideSharedLayout" or "overrideLayout")
            if schema.STYLE_LAYOUT_KEYS[field] or schema.STYLE_SHARED_LAYOUT_KEYS[field] then keys[#keys + 1] = root .. "overrideStyle" end
        end
    end
    return M.ControlSchema.Family(keys)
end
local function UnitRuleSetting(unit, lane, field, blacklist)
    local keys, schema = {}, MSUF.MSUF_Auras3.LaneKeySchema
    for _, runtimeUnit in ipairs(schema.UNIT_FAMILIES[unit] or { unit }) do
        local root = "auras3.perUnit." .. runtimeUnit .. "."
        keys[#keys + 1] = root .. (blacklist and "blacklist." or "filters.")
            .. (lane == "buff" and "buffs." or "debuffs.") .. field
        keys[#keys + 1] = root .. (blacklist and "overrideBlacklist" or "overrideFilters")
    end
    return M.ControlSchema.Family(keys)
end
local function CustomSetting(page, path)
    local unit = page:match("^uf_(.+)$")
    if not unit then return nil end
    local suffix = path:match("^custom%-container%.(.+)$")
    if not suffix then return nil end
    local field = CUSTOM_SETTING_FIELDS[suffix]
    local container, order = suffix:match("^(custom%d+)%.ordering%.(.+)$")
    if order then
        field = order == "sort-direction" and "placed.sortReverse" or "placed.sortMethod"
        local root = "auras3.customContainers.perUnit." .. unit .. ".items." .. container:match("%d+")
        if order == "sort-direction" then return root .. "." .. field end
        return M.ControlSchema.Fields({ root }, { field, "placed.sortReverse", "prioritySpellIDs" })
    end
    local preset, role = suffix:match("^(player%-defensives)%.(.+)$")
    if not preset then preset, role = suffix:match("^(target%-dots)%.(.+)$") end
    if preset then
        local fields = { enabled = "enabled", ["portrait-icon"] = "portraitIcon", ["portrait-max-icons"] = "portraitMaxIcons",
            ["portrait-cooldown-text"] = "portraitCooldownText", ["portrait-position-when-disabled"] = "portraitPositionWhenDisabled",
            ["auto-blacklist"] = "autoBlacklistPlayerBuffs", ["auto-blacklist-debuffs"] = "autoBlacklistDebuffs" }
        if not fields[role] then return nil end
        return "auras3.customContainers.perUnit." .. unit .. ".items.4." .. fields[role]
    end
    if not field then return nil end
    local keys = {}
    local fields = { field }
    if suffix == "effect.opacity" then fields[#fields + 1] = "frame.tintAlpha"
    elseif suffix == "setup.aura-type" then fields[#fields + 1] = "filters.maxDuration"
    elseif suffix == "filters.raid" then fields[#fields + 1] = "filters.exclusive"
    elseif suffix == "filters.cancelable" then fields[#fields + 1] = "filters.notCancelable"
    elseif suffix == "filters.notcancelable" then fields[#fields + 1] = "filters.cancelable" end
    for _, target in ipairs(fields) do
        for index = 1, unit == "pet" and 3 or 4 do
            keys[#keys + 1] = "auras3.customContainers.perUnit." .. unit .. ".items." .. index .. "." .. target
        end
    end
    return M.ControlSchema.Family(keys)
end
local function StyleSetting(page, path)
    local lane, token = path:match("^style%.lane%.([%w]+)%.(.+)$")
    if token == "auras3-icon-shape" then
        local kind = lane == "playerdefensives" and "playerDefensives" or lane == "targetdots" and "targetDots" or lane
        return "auras3.shared.appearanceIconShapes." .. kind
    end
    local field = STYLE_SETTING_FIELDS[token]
    local effect = token and token:match("^full%-frame%.(.+)$")
    if lane and field or effect then
        local schema = MSUF.MSUF_Auras3.LaneKeySchema
        if effect then field = lane .. "FrameEffect" .. (effect == "alpha" and "Color" or effect:gsub("^%l", string.upper))
        else field = (schema.LANE_STYLE_KEYS[lane] or {})[field] or field end
        local unit = page:match("^uf_(.+)$") or "shared"
        if token == "auras3-debuff-type-border-mode" then return UnitLayoutSetting(unit, { field, "useDebuffTypeBorders" }) end
        return UnitLayoutSetting(unit, { field })
    end
    local appearance = path:match("^style%.appearance%.icon%-style%.(.+)$")
    if appearance then
        local fields = { ["border-style"] = "styleBorderStyle", styleborderenabled = "styleBorderEnabled",
            styleborderthickness = "styleBorderThickness", ["stylebordercolor-alpha"] = "styleBorderColor",
            styleshadowenabled = "styleShadowEnabled", styleshadowsize = "styleShadowSize", ["styleshadowcolor-alpha"] = "styleShadowColor" }
        field = fields[appearance]
        if field then
            return { patterns = { "^auras3%.shared%.appearanceIconStyles%.[%a]+%." .. field .. "$" } }
        end
    end
    local fixed = { ["style.appearance.blizzard-aura-frames.hide-buffs"] = "hideBlizzardBuffFrame",
        ["style.appearance.blizzard-aura-frames.hide-debuffs"] = "hideBlizzardDebuffFrame",
        ["style.appearance.native-flow.weapon-enchants"] = "showWeaponEnchants" }
    return fixed[path] and "auras3.shared." .. fixed[path]
end
local function ScopedAuraSetting(page, path)
    local lane, token = path:match("^group%-style%.lane%.([%w]+)%.(.+)$")
    if not lane then lane, token = path:match("^group%-workspace%.lane%.([%w]+)%.layout%.(.+)$") end
    if not lane then lane, token = path:match("^group%-workspace%.lane%.([%w]+)%.filters%.(.+)$") end
    local field = STYLE_SETTING_FIELDS[token]
    if token == "max-duration" then field = "blacklist.maxDuration" end
    if token and token:match("^native%.") then field = "filterToken" end
    if lane and field then
        if token == "dispel-border-mode" then
            local keys = M.ControlSchema.GroupKeys("auras." .. lane .. ".dispelBorderMode").keys
            for _, key in ipairs(M.ControlSchema.GroupKeys("auras." .. lane .. ".showDispelBorder").keys) do keys[#keys + 1] = key end
            for _, key in ipairs(M.ControlSchema.GroupKeys("auras." .. lane .. ".showDispelSymbol").keys) do keys[#keys + 1] = key end
            return M.ControlSchema.Family(keys)
        end
        return M.ControlSchema.GroupKeys("auras." .. lane .. "." .. field)
    end
    if path == "group-style.root.dynamicscale" then return M.ControlSchema.GroupKeys("auras.dynamicScale") end
    lane, token = path:match("^unit%-workspace%.lane%.([%w]+)%.layout%.(.+)$")
    if not lane then lane, token = path:match("^unit%-workspace%.lane%.([%w]+)%.filters%.(.+)$") end
    field = STYLE_SETTING_FIELDS[token]
    local unit = page:match("^uf_(.+)$")
    if unit and lane and field then
        if token == "max-duration" then return UnitRuleSetting(unit, lane, "maxDuration", true) end
        local names = { anchor = "anchorKey", growth = "growthKey", ["icon-height"] = "heightPercentKey",
            ["icon-size"] = "sizeKey", layer = "layerKey", ["max-icons"] = "maxKey", ["per-row"] = "perRowKey", spacing = "spacingKey" }
        local spec = MSUF.MSUF_Auras3.LaneKeySchema.LANE_SPECS[lane]
        local key = names[token] and spec[names[token]]
        if not key then return nil end
        if token == "growth" then return UnitLayoutSetting(unit, { key, spec.wrapKey }) end
        return UnitLayoutSetting(unit, { key })
    end
end

local function UnitWorkspaceSetting(page, path)
    local unit = page:match("^uf_(.+)$")
    local lane, part, token = path:match("^unit%-workspace%.lane%.([%a]+)%.([%a]+)%.(.+)$")
    if not unit or not lane then return nil end
    local schema = MSUF.MSUF_Auras3.LaneKeySchema
    if part == "layout" and token == "visible" then
        local setting = UnitLayoutSetting(unit, { schema.LANE_SPECS[lane].showKey, schema.LANE_SPECS[lane].maxKey })
        setting.keys[#setting.keys + 1] = "auras3.enabled"
        local runtimeUnit = (schema.UNIT_FAMILIES[unit] or { unit })[1]
        setting.keys[#setting.keys + 1] = "auras3." .. schema.UNIT_FLAG[runtimeUnit]
        return setting
    end
    if part ~= "filters" then return nil end
    if token == "hide-permanent" or token == "max-duration" then
        return UnitRuleSetting(unit, lane, token == "hide-permanent" and "hidePermanent" or "maxDuration", true)
    end
    -- Enabling an exclusive native filter clears its sibling classifications.
    -- These are the same native rule fields as the existing switch owner.
    local names = { ["only-mine"] = "onlyMine", ["non-player"] = "nonPlayer", onlymine = "onlyMine", nonplayer = "nonPlayer",
        onlyimportant = "onlyImportant", raidincombat = "raidInCombat", includenameplateonly = "includeNameplateOnly",
        includedispellable = "includeDispellable", dispellableany = "dispellableAny", externaldefensive = "externalDefensive",
        bigdefensive = "bigDefensive", notcancelable = "notCancelable", crowdcontrol = "crowdControl" }
    local field = names[token] or token
    local fields = { field }
    if field == "onlyMine" then
        if lane == "debuff" then fields[#fields + 1] = "nonPlayer" end
        if M.CLASSIC_AURA_FILTERS_REDUCED then fields[#fields + 1] = "enabled" end
    elseif field == "nonPlayer" and M.CLASSIC_AURA_FILTERS_REDUCED then fields = { "nonPlayer", "onlyMine", "enabled" }
    elseif field ~= "enabled" and field ~= "includeNameplateOnly" then
        fields = { "onlyImportant", "raid", "raidInCombat", "includeDispellable", "dispellableAny", "exclusive" }
        local extra = lane == "buff" and { "externalDefensive", "bigDefensive", "cancelable", "notCancelable" }
            or { "crowdControl", "nonPlayer" }
        for _, key in ipairs(extra) do fields[#fields + 1] = key end
        if lane == "debuff" and field == "nonPlayer" then fields[#fields + 1] = "onlyMine" end
    end
    local keys = {}
    for _, field in ipairs(fields) do
        for _, key in ipairs(UnitRuleSetting(unit, lane, field, false).keys) do keys[#keys + 1] = key end
    end
    return M.ControlSchema.Family(keys)
end
-- Named aura actions mutate the same records as their existing model owners.
local function AuraActionSetting(meta)
    local key, args = meta.actionKey, meta.actionFixedArgs or {}
    local scope, lane = args.scope, args.lane
    if key == "aura_custom_whitelist_add_spell" or key == "reset_aura_custom_container"
        or key == "aura_custom_reminder_enchant_item" then
        local path = "auras3.customContainers.perUnit." .. scope .. ".items." .. args.index
        if key == "aura_custom_reminder_enchant_item" then path = path .. ".reminderEnchantItem" end
        return path
    end
    if key == "aura_group_blacklist_add_spell" or key == "aura_group_blacklist_add_preset"
        or key == "aura_group_blacklist_remove_spell" then
        return M.ControlSchema.Family(M.ControlSchema.GroupKeys("auras." .. lane .. ".blacklist").keys,
            nil, { "^gf_[%a]+%.auras%.renderer$" })
    end
    if key == "aura_blacklist_add_spell" or key == "aura_blacklist_add_preset" then
        local keys = {}
        local family = MSUF.MSUF_Auras3.LaneKeySchema.UNIT_FAMILIES[scope] or { scope }
        for _, unit in ipairs(family) do
            keys[#keys + 1] = "auras3.perUnit." .. unit .. ".blacklist." .. (lane == "buff" and "buffs" or "debuffs")
            keys[#keys + 1] = "auras3.perUnit." .. unit .. ".overrideBlacklist"
        end
        return M.ControlSchema.Family(keys)
    end
end

-- pageFallback names the page key used when neither ctx nor the menu has one.
local function AuraControlMeta(ctx, path, classification, routeContract, pageFallback)
    path = tostring(path or "control"):lower():gsub("[^%w%._/-]+", "-")
    path = path:gsub("/", "."):gsub("^%.+", ""):gsub("%.+$", "")
    local pageKey = AuraCatalogPageKey(ctx and ctx.key or M.activeKey, pageFallback or "auras")
    local identity = "auras." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. "." .. identity,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = "auras/" .. path:gsub("%.", "/"),
        classification = classification or "setting",
        ephemeral = classification == "ephemeral" or nil,
    }
    if type(routeContract) == "string" and routeContract ~= "" then
        meta.settingKey = routeContract
    elseif type(routeContract) == "table" then
        meta.settingKey = routeContract.settingKey
        meta.setting = routeContract.setting
        meta.actionKey = routeContract.actionKey
        meta.actionFixedArgs = routeContract.actionFixedArgs
        meta.actionInputArg = routeContract.actionInputArg
        meta.searchSettingKeys = routeContract.searchSettingKeys
        meta.searchSettingKeyPatterns = routeContract.searchSettingKeyPatterns
    end
    if meta.classification == "action" then meta.setting = meta.setting or AuraActionSetting(meta) end
    if meta.classification == "setting" then
        meta.setting = meta.setting or CustomSetting(pageKey, path) or StyleSetting(pageKey, path)
            or UnitWorkspaceSetting(pageKey, path) or ScopedAuraSetting(pageKey, path)
        if path == "unit-workspace.container-selector" or path == "unit-workspace.tool-selector" then
            meta.schemaEphemeralReason = "Selects an aura editor workspace; no profile setting is written."
        end
    end
    if pageKey == "gf_auras" and meta.setting then
        local setting = meta.setting
        if type(setting) == "string" then setting = M.ControlSchema.Family({ setting }) end
        setting.keys = setting.keys or {}
        for _, key in ipairs(M.ControlSchema.GroupKeys("auras.renderer").keys) do setting.keys[#setting.keys + 1] = key end
        meta.setting = setting
    end
    return AttachSearchView(ctx, meta)
end

local function AuraControlMetaAtVisiblePath(ctx, identityPath, visiblePath, classification, routeContract)
    local meta = AuraControlMeta(ctx, identityPath, classification, routeContract)
    visiblePath = tostring(visiblePath or identityPath or "control"):lower():gsub("[^%w%._/-]+", "-")
    visiblePath = visiblePath:gsub("/", "."):gsub("^%.+", ""):gsub("%.+$", "")
    meta.controlPath = "auras/" .. visiblePath:gsub("%.", "/")
    return meta
end

local function RegisterAuraControl(ctx, widget, label, kind, path, classification, navigationKey)
    if not widget or type(M.RegisterSearchWidget) ~= "function" then return widget end
    local meta = AuraControlMeta(ctx, path, classification,
        type(navigationKey) == "table" and navigationKey or nil)
    meta.label = label
    meta.kind = kind
    if classification == "navigation" then
        meta.navigationKey = navigationKey
    elseif classification == "action" then
        if type(navigationKey) == "string" then meta.actionKey = navigationKey end
    end
    M.RegisterSearchWidget(widget, meta)
    return widget
end

local function RegisterAuraTextAction(ctx, widget, input, label, path, routeContract)
    if widget then
        widget._msuf2CommandAction = {
            kind = "button",
            valueKind = "text",
            set = function(value)
                value = tostring(value or "")
                if input and input.SetText then input:SetText(value) end
                local handler = type(widget.GetScript) == "function" and widget:GetScript("OnClick") or nil
                if type(handler) ~= "function" then return false end
                return handler(widget, "LeftButton", false)
            end,
        }
    end
    return RegisterAuraControl(ctx, widget, label, "button", path, "action", routeContract)
end

local function AddTooltip(widget, title, body)
    return M.AddTooltip(widget, title, body, {
        hook = true,
        titleAsLine = true,
        labelHit = true,
        labelHitWhenDisabled = true,
    })
end

local function AddCasterFilterTooltip(widget, lane)
    return AddTooltip(widget, "Only mine", lane == "debuff"
        and "Only Debuffs applied by the player."
        or "Only auras applied by the player.")
end

local AURA_TOOLTIP_HELP = "Controls this aura lane independently. Always / Out of Combat / Modifier / Never under %s affect only unit and group frames. "
    .. "Auras only reuse the selected Blizzard/MSUF look and cursor placement."
local function AddAuraTooltipHelp(widget)
    return AddTooltip(widget, "Aura tooltip", M.Format(AURA_TOOLTIP_HELP, M.NavPath("opt_misc", "Unitframe tooltips")))
end

local function ActionButton(parent, label, width, role)
    if W.RoleButton then return W.RoleButton(parent, label, role or "normal", width or 90, 24) end
    if W.TopButton then return W.TopButton(parent, label, width or 90, 24) end
    local btn = T.Button(parent, label, width or 90, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(btn) end
    return btn
end

local Card = W.ThemedControlCard

local function RefreshFallback(ctx)
    if M.RequestRefresh then
        M.RequestRefresh(ctx, "auras-rebuild-fallback")
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end

--- Shows the page again after a workspace selector (Container:, Edit:, lane)
--- or a structural edit. The aura pages declare their selectors as views
--- (spec.variantKey), so a selector click switches to that view's cached entry
--- or builds it once; any other call rebuilds the page. Nested aura workspaces
--- and pinned previews settle their final height after the page is selected;
--- the shared helper reapplies the viewport for us.
local function Rebuild(ctx)
    local key = (ctx and ctx.key) or M.activeKey or "auras3"
    if M.RebuildPageKeepingScroll and M.RebuildPageKeepingScroll(key) then return end
    RefreshFallback(ctx)
end

--- A list edit (add, remove, reorder, keep) or a setting whose controls only
--- refresh: the refreshers repaint pooled rows, so the page on screen repaints
--- in place. A rebuild would leave a whole frame tree behind, and WoW never
--- frees a frame.
local REPAINT_IN_PLACE = { inPlace = true }
local function Repaint(ctx)
    local key = (ctx and ctx.key) or M.activeKey or "auras3"
    if M.RepaintPageAfterDataChange and M.RepaintPageAfterDataChange(key, "auras-list", REPAINT_IN_PLACE) then return end
    RefreshFallback(ctx)
end

local function RequestAuraRuntime(scope, reason)
    return ApplyService.RequestAuras(scope or "shared", reason or "AURAS3_MENU2_BATCH")
end

local function ConfigureAuraSpellPriorityDrag(row, handle, listChild, rowHeight, onDrop)
    if not (row and handle and listChild) then return end
    rowHeight = max(1, tonumber(rowHeight) or 1)
    row:SetMovable(true)
    handle:RegisterForDrag("LeftButton")
    handle:EnableMouse(true)
    local function SnapRow()
        local slot = max(1, tonumber(row._displayIndex) or 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((slot - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((slot - 1) * rowHeight))
    end
    local function ClearDragState(shouldSnap)
        if row.StopMovingOrSizing then row:StopMovingOrSizing() end
        if row.SetFrameStrata and row._msufA3OldStrata then row:SetFrameStrata(row._msufA3OldStrata) end
        row._msufA3OldStrata = nil
        row._msufA3Dragging = nil
        if shouldSnap == true then SnapRow() end
    end
    handle:HookScript("OnEnter", function()
        if row._dragEnabled ~= true or not row.SetBackdropBorderColor then return end
        local c = (T.colors and T.colors.coreBlue) or { 0.095, 0.360, 0.560, 0.95 }
        row:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end)
    handle:HookScript("OnLeave", function()
        if not row.SetBackdropBorderColor then return end
        local c = (T.colors and (T.colors.cardBorder or T.colors.borderSoft)) or { 0.210, 0.230, 0.300, 0.78 }
        row:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end)
    handle:SetScript("OnDragStart", function()
        if row._dragEnabled ~= true or not row._spellID then return end
        if GameTooltip then GameTooltip:Hide() end
        row._msufA3Dragging = true
        row._msufA3OldStrata = row.GetFrameStrata and row:GetFrameStrata() or nil
        if row.SetFrameStrata then row:SetFrameStrata("TOOLTIP") end
        row:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        if row._msufA3Dragging ~= true then return end
        if row.StopMovingOrSizing then row:StopMovingOrSizing() end
        local _, centerY = row:GetCenter()
        local top = listChild.GetTop and listChild:GetTop()
        local count = max(1, tonumber(row._entryCount) or 1)
        local source = max(1, min(count, tonumber(row._displayIndex) or 1))
        local target, bestDistance = source, math.huge
        if centerY and top then
            local rowHalf = (row.GetHeight and row:GetHeight() or rowHeight) * 0.5
            for slot = 1, count do
                local distance = math.abs(centerY - (top - ((slot - 1) * rowHeight) - rowHalf))
                if distance < bestDistance then
                    target, bestDistance = slot, distance
                end
            end
        end
        local spellID = row._spellID
        ClearDragState(true)
        if spellID and target ~= source and type(onDrop) == "function" then onDrop(spellID, target) end
    end)
    row:HookScript("OnHide", function() ClearDragState(false) end)
end

local function QueueAurasPageRefresh(ctx, reason)
    if AurasMenuCombatLocked() then return false end
    if M.RequestRefresh then
        M.RequestRefresh(ctx, reason or "auras-refresh")
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end

local auraPageRefreshQueued = false

local pendingAuraPageRefreshCtx

local pendingAuraPageRefreshReason

local function QueueAuraPageControlRefresh(ctx, reason)
    pendingAuraPageRefreshCtx = ctx or pendingAuraPageRefreshCtx
    pendingAuraPageRefreshReason = reason or pendingAuraPageRefreshReason
    if auraPageRefreshQueued then return end
    auraPageRefreshQueued = true
    local function Flush()
        auraPageRefreshQueued = false
        local refreshCtx, refreshReason = pendingAuraPageRefreshCtx, pendingAuraPageRefreshReason
        pendingAuraPageRefreshCtx, pendingAuraPageRefreshReason = nil, nil
        if not AurasMenuCombatLocked() then QueueAurasPageRefresh(refreshCtx, refreshReason or "auras-apply") end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Flush) else Flush() end
end

local function ApplyUnit(ctx, unit, reason, refresh)
    reason = reason or "AURAS3_MENU2"
    RequestAuraRuntime(unit or "shared", reason)
    if refresh == true then QueueAuraPageControlRefresh(ctx, reason) end
end

local function ConfigureMaxDurationSlider(slider)
    if not slider then return slider end
    if slider.SetValueFormatter then
        slider:SetValueFormatter(function(value)
            value = Round(value)
            return value <= 0 and "Off" or (tostring(value) .. "s")
        end)
    end
    if slider.SetValueParser then
        slider:SetValueParser(function(value)
            value = tostring(value or ""):lower()
            if value == "off" then return 0 end
            return tonumber(value:match("%d+"))
        end)
    end
    AddTooltip(slider, "Maximum duration",
        "Off shows auras of any duration. Otherwise, auras whose total duration exceeds this number of seconds are hidden.")
    return slider
end

local UNIT_AURA_WORKSPACE_TAB_STYLE = {
    bg = { 0.012, 0.025, 0.052, 0.90 },
    border = { 0.070, 0.130, 0.235, 0.52 },
    textColor = { 0.78, 0.86, 0.97, 0.96 },
    hoverBg = { 0.024, 0.052, 0.100, 0.96 },
    hoverBorder = { 0.120, 0.245, 0.455, 0.78 },
    activeBg = { 0.032, 0.090, 0.205, 0.97 },
    activeBorder = { 0.150, 0.385, 0.760, 0.92 },
    activeTextColor = { 0.94, 0.98, 1.00, 1.00 },
}

local function UnitAuraWorkspaceTabButton(parent, item, width)
    -- Midnight is the authored reference and must keep its exact tuned values.
    -- Other menu accents resolve from the live token family so Preview-as and
    -- Sample/Live do not retain the blue literals baked when this file loaded.
    if T.MenuAccentActive and T.MenuAccentActive() then
        local colors = T.colors or {}
        local style = UNIT_AURA_WORKSPACE_TAB_STYLE
        local function SetColor(target, source)
            target[1], target[2], target[3] = source[1], source[2], source[3]
        end
        SetColor(style.bg, colors.coreShadow or style.bg)
        SetColor(style.border, colors.coreRim or style.border)
        SetColor(style.textColor, colors.pillText or style.textColor)
        SetColor(style.hoverBg, colors.coreSurface or style.hoverBg)
        SetColor(style.hoverBorder, colors.coreGlow or style.hoverBorder)
        SetColor(style.activeBg, colors.pillActive or colors.coreBlue or style.activeBg)
        SetColor(style.activeBorder, colors.pillEdgeActive or colors.coreHot or style.activeBorder)
        SetColor(style.activeTextColor, colors.pillTextActive or style.activeTextColor)
    end
    return W.TopButton(parent, item.text, width, 24, UNIT_AURA_WORKSPACE_TAB_STYLE)
end

-- schemaScope opts the tab buttons into a schema declaration (ephemeral menu state).
local function BuildActionTabs(ctx, parent, values, x, y, width, getValue, setValue, gap, buttonFactory, catalogPath, schemaScope)
    gap = gap or 6
    local count = #values
    local bw = max(56, floor(((width or 720) - gap * (count - 1)) / count))
    local buttons = {}
    local RefreshButtons
    for i = 1, count do
        local item = values[i]
        -- Tab rows show a selection, so they default to the workspace tab
        -- style: the plain action-button style draws its active state exactly
        -- like its idle one, so a selected chip would look unselected.
        local btn = (buttonFactory and buttonFactory(parent, item, bw)) or UnitAuraWorkspaceTabButton(parent, item, bw)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        btn._msuf2Value = item.value
        btn:SetScript("OnClick", function()
            if item.value == getValue() then return end
            W.BeginSelectionMotion(btn, item.value)
            setValue(item.value)
            -- Selecting a tab is menu state, not a page rebuild, so re-stamp
            -- the active chip here instead of waiting for a page refresh.
            if RefreshButtons then RefreshButtons() end
        end)
        RegisterAuraControl(ctx, btn, item.text or item.label or item.value or "Option", "button",
            (catalogPath or "workspace.tabs") .. ".option." .. AuraCatalogToken(item.value, tostring(i)), "ephemeral")
        if schemaScope then M.ControlSchema.Owned(btn, schemaScope, "menuState") end
        buttons[i] = btn
        if item.value ~= nil then buttons[item.value] = btn end
    end
    RefreshButtons = function()
        local current = getValue()
        for i = 1, count do
            if buttons[i].SetActive then buttons[i]:SetActive(values[i].value == current) end
        end
    end
    W.AttachSelectionMotion(parent, buttons, false, catalogPath)
    RefreshButtons()
    M.TrackRefresh(ctx, RefreshButtons)
    return getValue(), buttons, RefreshButtons
end

--- The blocked-spell list of a unit or group blacklist section: the empty
--- state text, a scroll list of rows (icon, name, Spell ID, Remove) built on
--- demand, and its repaint through the search query. opts.remove(spellID)
--- removes one entry; opts.removePath(value) names its Remove button.
--- The trimmed lower-case search query and the spell list entries whose
--- name or spell ID contains it (every entry for an empty query).
local function FilterSpellEntries(entries, searchValue)
    local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local visible = {}
    for i = 1, #entries do
        local entry = entries[i]
        local haystack = (tostring(entry.text or "") .. " "
            .. tostring(entry.spellID or entry.value or "")):lower()
        if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
    end
    return query, visible
end
--- A scrolling spell list in an aura section: the scroll frame at (24, y),
--- height px tall, and its child, styled like the other nested lists.
local function SpellListScroll(section, y, inner, height)
    local listScroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, section))
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, y)
    listScroll:SetSize(inner - 20, height)
    local listChild = PixelLayoutRegion(CreateFrame("Frame", nil, listScroll))
    listChild:SetSize(inner - 44, height)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, 44)
    return listScroll, listChild
end
--- Row i of a 44 px spell list: a 40 px card across the list child.
local function SpellListRow(listChild, i)
    local row = PixelLayoutRegion(CreateFrame("Frame", nil, listChild))
    row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
    row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
    row:SetHeight(40)
    if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return row
end
--- A spell list row's icon (left edge at iconAnchor's iconRelPoint, x px
--- in), the name and Spell ID lines beside it and its Remove button.
local function SpellListRowLabels(row, iconAnchor, iconRelPoint, x)
    row.icon = PixelLayoutRegion(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetPoint("LEFT", iconAnchor, iconRelPoint, x, 0)
    row.icon:SetSize(28, 28)
    row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
    row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
    row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
    row.remove = ActionButton(row, "Remove", 80)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
end
--- Row i of a compact 24 px spell list: a 20 px button across the list child
--- with a 17 px icon and the spell name; a click runs onClick(row).
local function CompactSpellRow(listChild, i, onClick)
    local row = PixelLayoutRegion(CreateFrame("Button", nil, listChild))
    row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 24))
    row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 24))
    row:SetHeight(20)
    row.icon = PixelLayoutRegion(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.icon:SetSize(17, 17)
    row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row:SetScript("OnClick", onClick)
    return row
end
local function BlockedSpellList(ctx, section, inner, offsetY, emptyText, opts)
    local Tr, MatchSuffix = M.AuraSettings.Tr, M.AuraSettings.MatchSuffix
    local empty = W.Text(section, emptyText, 24, -284 + offsetY, inner, T.colors.muted)
    local listScroll, listChild = SpellListScroll(section, -260 + offsetY, inner, 150)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = SpellListRow(listChild, i)
        SpellListRowLabels(row, row, "LEFT", 7)
        row.remove:SetScript("OnClick", function()
            if row._spellID then opts.remove(row._spellID) end
        end)
        AddTooltip(row.remove, "Remove from blacklist", "Stops blocking this aura.")
        rows[i] = row
        return row
    end
    local list = {}
    --- Repaints the rows for the entries matching searchValue and the
    --- prepared header's count.
    function list.Paint(entries, searchValue, prepared)
        local query, visible = FilterSpellEntries(entries, searchValue)
        T.SetTranslatedText(prepared, M.Format("Blocked spells (%d)", #entries) .. MatchSuffix(query, #visible))
        T.SetTranslatedText(empty, #entries == 0 and Tr(emptyText) or M.Format("No results for \"%s\".", query))
        empty:SetShown(#visible == 0)
        listScroll:SetShown(#visible > 0)
        listChild:SetHeight(max(150, #visible * 44))
        for i = 1, max(#rows, #visible) do
            local row, entry = rows[i], visible[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.value
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local name = tostring(entry.text or entry.value or "Spell"):gsub("%s*%(#%d+%)$", "")
                row.name:SetText(name)
                row.id:SetText(entry.spellID and (M.Format("Spell ID %s", tostring(entry.spellID))) or tostring(entry.value or ""))
                RegisterAuraControl(ctx, row.remove, M.Format("Remove %s", name), "button", opts.removePath(entry.value), "action")
                if opts.schemaScope then M.ControlSchema.Owned(row.remove, opts.schemaScope, "auras") end
                row:Show()
            elseif row then
                row._spellID = nil
                row:Hide()
            end
        end
    end
    return list
end

--- A blacklist's blocked spells as a set keyed by tostring(spell id).
local function BlockedSet(entries)
    local blocked = {}
    for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
    return blocked
end
--- The spell a blacklist's "Add spell" button adds: the selected preset
--- spell while it is not blocked yet, otherwise the first one that is not.
local function FirstUnblockedSpell(values, selected, blocked)
    for i = 1, #values do
        if values[i].value == selected and not blocked[tostring(selected)] then return selected end
    end
    for i = 1, #values do
        if values[i].value ~= nil and not blocked[tostring(values[i].value)] then return values[i].value end
    end
    return nil
end
--- The preset summary line ("n spells in this set - ...") and the enabled
--- state of the "Add set" and "Add spell" buttons for the blocked set.
local function PaintPresetSummary(selectedSummary, addSet, addSpell, setSpells, blocked, CurrentSpell)
    local missing = 0
    for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
    T.SetTranslatedText(selectedSummary, missing == 0
        and M.Format("%d spells in this set - all already blocked", #setSpells)
        or M.Format("%d spells in this set - %d can still be added", #setSpells, missing))
    W.SetControlEnabled(addSet, missing > 0)
    local selectedSpell = CurrentSpell()
    W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
end

local function BuildLaneTabs(ctx, parent, stateKey, x, y, width, schemaScope)
    BuildActionTabs(ctx, parent, LANE_VALUES, x, y, width, function() return CurrentLane(stateKey, "debuff") end, function(value)
        SetCurrentLane(stateKey, value)
        Rebuild(ctx)
    end, nil, nil, "workspace.lane-selector." .. AuraCatalogToken(stateKey, "lane"), schemaScope)
end

M.AuraControls = {
    ActionButton = ActionButton,
    AddAuraTooltipHelp = AddAuraTooltipHelp,
    AddCasterFilterTooltip = AddCasterFilterTooltip,
    AddTooltip = AddTooltip,
    ApplyUnit = ApplyUnit,
    AuraCatalogToken = AuraCatalogToken,
    AuraControlMeta = AuraControlMeta,
    ConfigureSearchView = ConfigureSearchView,
    AttachSearchView = AttachSearchView,
    AuraControlMetaAtVisiblePath = AuraControlMetaAtVisiblePath,
    BlockedSet = BlockedSet,
    BlockedSpellList = BlockedSpellList,
    BuildLaneTabs = BuildLaneTabs,
    Card = Card,
    CompactSpellRow = CompactSpellRow,
    SpellListRow = SpellListRow,
    SpellListRowLabels = SpellListRowLabels,
    SpellListScroll = SpellListScroll,
    FilterSpellEntries = FilterSpellEntries,
    FirstUnblockedSpell = FirstUnblockedSpell,
    PaintPresetSummary = PaintPresetSummary,
    ConfigureAuraSpellPriorityDrag = ConfigureAuraSpellPriorityDrag,
    ConfigureMaxDurationSlider = ConfigureMaxDurationSlider,
    LANE_VALUES = LANE_VALUES,
    QueueAurasPageRefresh = QueueAurasPageRefresh,
    Rebuild = Rebuild,
    Repaint = Repaint,
    RegisterAuraControl = RegisterAuraControl,
    RegisterAuraTextAction = RegisterAuraTextAction,
    RequestAuraRuntime = RequestAuraRuntime,
}
