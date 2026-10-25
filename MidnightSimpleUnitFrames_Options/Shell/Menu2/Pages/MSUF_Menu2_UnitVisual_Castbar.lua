-- Castbar state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.UnitVisualFactories = M.UnitVisualFactories or {}

M.UnitVisualFactories.Castbar = function(
    MSUF, M, FILE, W, Schema, ControlRow, SectionCard, SectionNote, CastbarsOnSettingsChanged, SuppressBlizzardPlayerCastbars,
    ShowReloadRecommendedPopup, floor, max, min, VT, CASTBAR_FIELDS, GetGeneral, UnitTopLabel, ReadBool, SetBool,
    ReadGeneralBool, SetGeneralBool, NormalizePortrait, SetPortraitValue, SettingMeta, ReviewedMeta, RegisterControl,
    UnitSectionShared, SetSectionHeaderStatus, CreateSectionNotice, NormalizeTabKey, CurrentTab, SetSectionBodyHeight,
    BuildSectionTabs, PrepareTabTarget
)

local CASTBAR_BACKEND_VALUES = VT("MSUF", "MSUF castbar", "BLIZZARD", "Blizzard castbar")
local CASTBAR_PREFIX = { player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast", arena = "arenaCast" }
-- Castbar width and height an unset key reads as: the values the defaults
-- pass seeds (State/Defaults/MSUF_Defaults_Bars.lua). One table for the
-- sliders, their reset values and the spell text width.
local CASTBAR_DEFAULT_SIZE = {
    player = { width = 271, height = 18 }, target = { width = 272, height = 18 },
    focus = { width = 175, height = 18 }, boss = { width = 176, height = 12 }, arena = { width = 176, height = 12 },
}
local CASTBAR_ICON_POSITIONS = VT("LEFT", "Left", "RIGHT", "Right", "INSIDE_LEFT", "Inside Left", "INSIDE_RIGHT", "Inside Right")
local CASTBAR_TEXT_POSITIONS = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right", "ABOVE", "Above", "BELOW", "Below")
local CASTBAR_TIME_FORMATS = VT("CURRENT", "Remaining", "ELAPSED", "Elapsed", "ELAPSED_MAX", "Elapsed / Total", "CURRENT_MAX", "Remaining / Total")
local CASTBAR_TAB_VALUES = VT("general", "General", "icon", "Icon", "spell", "Spell Text", "time", "Time Text", "advanced", "Advanced")
--- The thickness slider owns on/off (0 hides the border); this picks how the
--- visible border is painted. "Castbar border color" is the only value the
--- Castbar Icon Border Color shortcut applies to.
local CASTBAR_ICON_BORDER_STYLES = VT("NONE", "None", "DARK", "Dark", "CASTBAR", "Castbar border color")
-- general grew by 32px when "Show interrupter name" pushed the Size card down.
local CASTBAR_TAB_HEIGHTS = { general = 424, icon = 540, spell = 386, time = 386, advanced = 480 }
local CASTBAR_WIDTH_SOURCE_VALUES = VT("manual", "Manual width", "unitframe", "Auto: Unit Frame", "essential", "Auto: Essential Cooldowns", "utility",
    "Auto: Utility Cooldowns")
local CASTBAR_TEXT_ALIGN = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right")
local CASTBAR_TRUNCATE_VALUES = VT("AUTO", "Auto fit", "CLIP", "Manual width", "NONE", "No width limit")
local function CastbarTabHeight(unit, tab)
    return CASTBAR_TAB_HEIGHTS[NormalizeTabKey(CASTBAR_TAB_HEIGHTS, tab)]
end
local function CurrentCastbarTab(unit)
    return CurrentTab("unitCastbarTabSelection", CASTBAR_TAB_HEIGHTS, unit)
end
local function PrepareCastbarSwitch(ctx, sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then Schema.Section(sec, unit) end
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local fields = CASTBAR_FIELDS[unit]
    local providerMemoryKey = fields.providerMemory or (fields.backend and (fields.backend .. "BeforeHide") or nil)
    local canUseBlizzardProvider = unit == "player"
    local state = {}
    -- The core functions resolve once per build: the refresh closures below read the backend on every setting change.
    local fnNormalizeForUnit = MSUF.Require("MSUF_NormalizeCastbarBackendForUnit", FILE)
    local fnGetBackend = MSUF.Require("MSUF_GetCastbarBackend", FILE)
    local fnSetBackend = MSUF.Require("MSUF_SetCastbarBackend", FILE)
    local function NormalizeBackend(value)
        return fnNormalizeForUnit(unit, value) or "MSUF"
    end
    local function ReadCastbarBackend()
        return NormalizeBackend(fnGetBackend(unit, GetGeneral()))
    end
    local function SetCastbarBackend(value)
        local backend = NormalizeBackend(value)
        local g = GetGeneral()
        if providerMemoryKey and backend ~= "HIDE" then g[providerMemoryKey] = backend end
        fnSetBackend(unit, backend, g)
        M.RequestUnitDomains(unit, "MSUF2_CASTBAR_BACKEND", { castbar = true, preview = true })
        CastbarsOnSettingsChanged("menu2_backend")
        if unit == "player" then SuppressBlizzardPlayerCastbars() end
        if state.refresh then state.refresh() end
    end
    local function ReadCastbarProvider()
        if not canUseBlizzardProvider then return "MSUF" end
        local backend = ReadCastbarBackend()
        if backend == "BLIZZARD" then return "BLIZZARD" end
        if backend == "MSUF" then return "MSUF" end
        local remembered = providerMemoryKey and NormalizeBackend(GetGeneral()[providerMemoryKey]) or nil
        if remembered == "BLIZZARD" then return "BLIZZARD" end
        return "MSUF"
    end
    local function SetCastbarProvider(value)
        if not canUseBlizzardProvider then return end
        local backend = NormalizeBackend(value)
        if backend == "HIDE" then backend = "MSUF" end
        local previousBackend = ReadCastbarBackend()
        SetCastbarBackend(backend)
        if backend == "BLIZZARD" and previousBackend ~= "BLIZZARD" then
            ShowReloadRecommendedPopup("Player Blizzard castbar")
        end
    end
    local function SetCastbarEnabled(enabled)
        if enabled then
            SetCastbarBackend(canUseBlizzardProvider and ReadCastbarProvider() or "MSUF")
        else
            local backend = ReadCastbarBackend()
            if providerMemoryKey and backend ~= "HIDE" then GetGeneral()[providerMemoryKey] = backend end
            SetCastbarBackend("HIDE")
        end
    end
    state.read, state.set = ReadCastbarBackend, SetCastbarBackend
    state.readProvider, state.setProvider = ReadCastbarProvider, SetCastbarProvider
    state.setEnabled = SetCastbarEnabled
    local enabled = ControlRow(ctx, sec, { "sectionSwitch", "enabled", true, { "Enable Castbar" },
        get = function() return ReadCastbarBackend() ~= "HIDE" end,
        customSetReason = "Coordinates the selected castbar provider, enabled state and dependent backend settings.", set = SetCastbarEnabled,
        scope = unit, setting = Schema.Family({ "general." .. fields.backend, "general." .. fields.enable,
            "general." .. providerMemoryKey }), meta = ReviewedMeta(ctx, "castbar.enabled", "setting", "compound",
            "Castbar visibility coordinates backend, enable state, and remembered provider."),
        beforeBind = function(widget)
            widget._msuf2CastbarState = state
            W.AttachUnitEditFocus(widget, unit, "castbar")
        end,
    })
    return enabled
end
-- The unit Castbar section builds in order through these functions; s carries
-- the section frame, its layout, the control lists and every binder, card
-- and control a later part or the closing gate group reads.
local CastbarSection = {}
function CastbarSection.Binders(s)
    local ctx, unit, prefix, allCastbarControls = s.ctx, s.unit, s.prefix, s.allCastbarControls
    local function AddControl(list, control)
        if control then
            allCastbarControls[#allCastbarControls + 1] = control
            if list then list[#list + 1] = control end
        end
        return control
    end
    local function DetailKey(suffix)
        return prefix and (prefix .. suffix) or suffix
    end
    local function CastbarWidthKey()
        if unit == "boss" then return "bossCastbarWidth" end
        if unit == "arena" then return "arenaCastbarWidth" end
        return prefix and (prefix .. "BarWidth") or nil
    end
    local function CastbarHeightKey()
        if unit == "boss" then return "bossCastbarHeight" end
        if unit == "arena" then return "arenaCastbarHeight" end
        return prefix and (prefix .. "BarHeight") or nil
    end
    -- Resolved once per build: ReadWidthSource runs on every castbar refresh.
    local fnWidthSourceKey = MSUF.Require("MSUF_GetCastbarWidthSourceKey", FILE)
    local fnNormalizeWidthSource = MSUF.Require("MSUF_NormalizeCastbarWidthSource", FILE)
    local function CastbarWidthSourceKey()
        local key = fnWidthSourceKey(unit)
        if key then return key end
        if unit == "player" then return "castbarPlayerMatchWidth" end
        if unit == "target" then return "castbarTargetMatchWidth" end
        if unit == "focus" then return "castbarFocusMatchWidth" end
        if unit == "boss" then return "bossCastbarMatchWidth" end
        if unit == "arena" then return "arenaCastbarMatchWidth" end
    end
    local function NormalizeWidthSource(value)
        return fnNormalizeWidthSource(value)
    end
    local function ReadWidthSource()
        local key = CastbarWidthSourceKey()
        return NormalizeWidthSource(key and GetGeneral()[key]) or "manual"
    end
    local function ReadGeneralValue(key, defaultValue)
        local value = GetGeneral()[key]
        if value == nil or value == "" then return defaultValue end
        return value
    end
    local function ReadGeneralNumber(key, defaultValue)
        local value = tonumber(GetGeneral()[key])
        if value == nil then value = defaultValue or 0 end
        return value
    end
    local function SetGeneralValue(key, value, reason)
        M.SetGeneralValue(key, value, reason, { castbar = true, preview = true, applyAll = false })
    end
    local function SetGeneralNumber(key, value, reason)
        value = tonumber(value)
        if value == nil then return end
        if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
        SetGeneralValue(key, value, reason)
    end
    local function PrepareControl(widget, row)
        if row.castbarControl then AddControl(nil, widget) end
        W.AttachUnitEditFocus(widget, unit, "castbar")
    end
    -- No castbar detail color binder lives here on purpose: every castbar text
    -- reaches its color through the card's three-dot shortcut and the Colors page,
    -- so this page never grows a second swatch for a key it already edits.
    local function BuildDetailControls(parent, list, rows)
        local options = Schema.UnitOptions()
        options.beforeBind = function(widget)
            AddControl(list, widget)
            W.AttachUnitEditFocus(widget, unit, "castbar")
        end
        for _, row in ipairs(rows) do
            local key, fallback, kind = row[2], row[3], row[1]
            row.get = function()
                if kind == "slider" then return ReadGeneralNumber(key, fallback) end
                return ReadGeneralValue(key, fallback)
            end
            if row.beforeSet and kind == "slider" then
                row.customSetReason = "Adjusts coupled text-width or truncation settings before the numeric write."
                row.write = {
                    call = kind == "slider" and SetGeneralNumber or SetGeneralValue, keyOnly = true,
                    args = { row.reason }, before = kind == "slider" and row.beforeSet or nil,
                    convert = function(value) if kind == "slider" then return value end return value or fallback end,
                    after = kind ~= "slider" and row.afterSet or nil
                } --[[schema setter: H4.UnitFrameVisuals.15]]
            else
                row.write = { call = kind == "slider" and SetGeneralNumber or SetGeneralValue,
                    keyOnly = true, args = { row.reason },
                    after = kind ~= "slider" and row.afterSet and function() row.afterSet() end or nil }
                    --[[schema setter: UnitFrameVisuals.DetailRows]]
                if kind ~= "slider" then row.write.fallback = fallback end
            end
            row.meta = SettingMeta(ctx, "castbar.detail." .. tostring(row.reason), "general", key)
            row.scope, row.roundStep = unit, kind == "slider"
        end
        return Schema.Build(ctx, parent, rows, options)
    end
    s.AddControl, s.DetailKey, s.CastbarWidthKey = AddControl, DetailKey, CastbarWidthKey
    s.CastbarHeightKey, s.CastbarWidthSourceKey = CastbarHeightKey, CastbarWidthSourceKey
    s.NormalizeWidthSource, s.ReadWidthSource = NormalizeWidthSource, ReadWidthSource
    s.ReadGeneralValue, s.ReadGeneralNumber, s.SetGeneralValue = ReadGeneralValue, ReadGeneralNumber, SetGeneralValue
    s.SetGeneralNumber, s.BuildDetailControls, s.PrepareControl = SetGeneralNumber, BuildDetailControls, PrepareControl
end
function CastbarSection.Cards(s)
    local ctx, unit, fields, sec, sectionW, leftX, leftW = s.ctx, s.unit, s.fields, s.sec, s.sectionW, s.leftX, s.leftW
    local rightX, rightW, RefreshCastbarEnabled, DetailKey = s.rightX, s.rightW, s.RefreshCastbarEnabled, s.DetailKey
    local ReadGeneralValue = s.ReadGeneralValue
    local castbarState = PrepareCastbarSwitch(ctx, sec, unit)._msuf2CastbarState
    castbarState.refresh = function() RefreshCastbarEnabled() end
    local ReadCastbarBackend, SetCastbarBackend = castbarState.read, castbarState.set
    local ReadCastbarProvider, SetCastbarProvider = castbarState.readProvider, castbarState.setProvider
    local SetCastbarEnabled = castbarState.setEnabled
    local controlWLeft = max(220, leftW - 58)
    local controlWRight = max(220, rightW - 58)
    local tabFrames = {}
    local generalTab, iconTab, spellTab, timeTab, advancedTab =
        UnitSectionShared.MakeTabFrames(sec, -64, sectionW, tabFrames, "general", "icon", "spell", "time", "advanced")
    local function Card(tab, name, args)
        return SectionCard(ctx, unit, tab, "castbar", name, args)
    end
    local generalCard = Card(generalTab, "generalCard", { nil, nil, leftX, -4, leftW, 164 })
    local providerCard = Card(generalTab, "providerCard", { "Provider & Surface", nil, rightX, -4, rightW, 164, "group" })
    local sizeCard = Card(generalTab, "sizeCard",
        { "Size", "Width can use manual bounds or follow another frame.", leftX, -186, sectionW - 32, 166, "group" })
    local iconCard = Card(iconTab, "iconCard", { nil, nil, leftX, -4, leftW, 424 })
    local portraitIconCard = Card(iconTab, "portraitIconCard", { "Portrait Cast Icon", nil, rightX, -4, rightW, 156, "group" })
    local spellCard = Card(spellTab, "spellCard", { nil, nil, leftX, -4, leftW, 270 })
    local targetNameCard = fields.targetName and Card(spellTab, "targetNameCard", { "Cast Target Text", nil, rightX, -4, rightW, 270, "group" }) or nil
    local timeCard = Card(timeTab, "timeCard", { nil, nil, leftX, -4, leftW, 270 })
    local textAdvancedCard = Card(advancedTab, "textAdvancedCard", { "Spell Text Behavior", nil, leftX, -4, leftW, 190, "group" })
    local iconAdvancedCard = Card(advancedTab, "iconAdvancedCard", { "Icon Style", nil, rightX, -4, rightW, 212, "group" })
    local layerAdvancedCard = Card(advancedTab, "layerAdvancedCard", { "Whole Castbar Layer", nil, rightX, -230, rightW, 164, "group" })
    if W.AttachContextColorReferences then
        local function GeneralCastbarColorRefs()
            local refs = {}
            local general = GetGeneral()
            if unit == "player" and general.playerCastbarOverrideEnabled == true then
                local mode = tostring(general.playerCastbarOverrideMode or "CLASS"):upper()
                refs[1] = mode == "CUSTOM" and "cast.player_override" or "unit.class.current"
            else
                refs[1], refs[2] = "cast.interruptible", "cast.non_interruptible"
            end
            refs[#refs + 1] = "cast.interrupt_feedback"
            return refs
        end
        local function IconBorderColorRefs()
            local style = tostring(ReadGeneralValue(DetailKey("IconBorderStyle"), "DARK")):upper()
            return style == "CASTBAR" and { "cast.border" } or {}
        end
        local castContext = function() return { unit = unit } end
        W.AttachContextColorReferences(generalCard, GeneralCastbarColorRefs, {
            title = M.Format("%s Castbar Colors", UnitTopLabel(unit)),
            note = "Player colors follow the active override mode.",
            historySource = "menu:unit-castbar-general-colors",
            context = castContext,
        })
        W.AttachContextColorReferences(providerCard, { "cast.background", "cast.border" }, {
            title = "Castbar Surface Colors",
            note = "Shared castbar background and outline colors.",
            historySource = "menu:unit-castbar-surface-colors",
        })
        W.AttachContextColorReferences(iconCard, IconBorderColorRefs, {
            title = "Castbar Icon Border Color",
            note = "Used by the Castbar icon-border style.",
            historySource = "menu:unit-castbar-icon-border-color",
        })
        local function AttachCastTextSettings(card, colorId, title, source)
            if not (card and W.AttachContextColorShortcut) then return end
            W.AttachContextColorShortcut(card, {
                title = title,
                historyLabel = title,
                historySource = source,
                textSettings = {
                    scope = "shared",
                    unit = unit,
                    kind = colorId == "cast.target_text.current" and "cast_target" or "cast",
                    colorReferences = { colorId },
                    colorContext = castContext,
                    colorTitle = title,
                    subtitle = "Castbar text follows the shared Fonts settings until this text gets its own color.",
                    capabilities = { baseline = false },
                },
            })
        end
        -- Each text gets its own detail reference. They resolve to the shared
        -- castbar text color while no per-castbar override exists, so the three
        -- cards no longer all edit one value behind three different labels.
        AttachCastTextSettings(spellCard, "cast.spell_text.current", "Cast Spell Text Color", "menu:unit-castbar-spell-text-color")
        if targetNameCard then
            AttachCastTextSettings(targetNameCard, "cast.target_text.current", "Cast Target Text Color", "menu:unit-castbar-target-text-color")
        end
        AttachCastTextSettings(timeCard, "cast.time_text.current", "Cast Time Text Color", "menu:unit-castbar-time-text-color")
        AttachCastTextSettings(textAdvancedCard, "cast.spell_text.current", "Cast Spell Text Color", "menu:unit-castbar-advanced-text-color")
        W.AttachContextColorReferences(iconAdvancedCard, IconBorderColorRefs, {
            title = "Castbar Icon Border Color",
            note = "Used by the Castbar icon-border style.",
            historySource = "menu:unit-castbar-advanced-icon-border-color",
        })
    end
    s.ReadCastbarBackend, s.SetCastbarBackend = ReadCastbarBackend, SetCastbarBackend
    s.ReadCastbarProvider, s.SetCastbarProvider = ReadCastbarProvider, SetCastbarProvider
    s.SetCastbarEnabled, s.controlWLeft, s.controlWRight = SetCastbarEnabled, controlWLeft, controlWRight
    s.tabFrames, s.generalTab = tabFrames, generalTab
    s.generalCard, s.providerCard, s.sizeCard, s.iconCard = generalCard, providerCard, sizeCard, iconCard
    s.portraitIconCard, s.spellCard, s.targetNameCard = portraitIconCard, spellCard, targetNameCard
    s.timeCard, s.textAdvancedCard, s.iconAdvancedCard = timeCard, textAdvancedCard, iconAdvancedCard
    s.layerAdvancedCard = layerAdvancedCard
end
function CastbarSection.Tabs(s)
    local ctx, unit, sec, sectionW = s.ctx, s.unit, s.sec, s.sectionW
    -- This custom workspace owns tab frames, exact-search navigation and section
    -- height. Its native controller retains selection; ordinary settings use rows.
    BuildSectionTabs(ctx, sec, unit, { stateKey = "unitCastbarTabSelection", heights = CASTBAR_TAB_HEIGHTS,
        values = CASTBAR_TAB_VALUES, width = min(620, sectionW - 48), frames = s.tabFrames,
        controlId = "castbar.workspace_tab", label = "Castbar area",
        afterRefresh = function(tab) SetSectionBodyHeight(sec, CastbarTabHeight(unit, tab), CASTBAR_TAB_HEIGHTS.general) end })
    s.BindExactCastbarTabTarget = function(widget, tab, settingKey)
        PrepareTabTarget(sec, "unitCastbarTab", widget, tab, settingKey)
    end
end
function CastbarSection.General(s)
    local ctx, unit, fields, sec, sectionW, rightW = s.ctx, s.unit, s.fields, s.sec, s.sectionW, s.rightW
    local RefreshCastbarEnabled, canUseBlizzardProvider = s.RefreshCastbarEnabled, s.canUseBlizzardProvider
    local CastbarWidthKey, CastbarHeightKey = s.CastbarWidthKey, s.CastbarHeightKey
    local CastbarWidthSourceKey, NormalizeWidthSource = s.CastbarWidthSourceKey, s.NormalizeWidthSource
    local ReadWidthSource, ReadGeneralNumber = s.ReadWidthSource, s.ReadGeneralNumber
    local SetGeneralValue, SetGeneralNumber = s.SetGeneralValue, s.SetGeneralNumber
    local ReadCastbarBackend, SetCastbarBackend = s.ReadCastbarBackend, s.SetCastbarBackend
    local ReadCastbarProvider, SetCastbarProvider = s.ReadCastbarProvider, s.SetCastbarProvider
    local SetCastbarEnabled, controlWRight, generalTab = s.SetCastbarEnabled, s.controlWRight, s.generalTab
    local generalCard, providerCard, sizeCard = s.generalCard, s.providerCard, s.sizeCard
    local BindExactCastbarTabTarget = s.BindExactCastbarTabTarget
    local castbarNotice, _, castbarNoticeButton = CreateSectionNotice(generalTab, -334, "Use MSUF", 96)
    if castbarNoticeButton then
        RegisterControl(castbarNoticeButton, ctx, "castbar.use_msuf", "Use MSUF", "button", "setting", {
            settingKey = "general." .. tostring(fields.enable),
            command = {
                kind = "toggle", valueKind = "boolean",
                get = function() return ReadCastbarBackend() ~= "HIDE" end,
                companionWrites = { "general." .. fields.backend,
                    "general." .. (fields.providerMemory or (fields.backend .. "BeforeHide")) },
                customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                    set = function(value) SetCastbarEnabled(value == true) end,
            },
        })
        castbarNoticeButton:SetScript("OnClick", function()
            SetCastbarBackend("MSUF")
        end)
        Schema.Owned(castbarNoticeButton, unit, "castbar")
    end
    local enabled = PrepareCastbarSwitch(ctx, sec, unit)
    local provider
    if canUseBlizzardProvider then
        provider = ControlRow(ctx, providerCard, { "dropdown", "provider", "MSUF", { "Castbar provider", CASTBAR_BACKEND_VALUES, min(260,
            controlWRight) }, { 16, -52, min(260, controlWRight) },
            get = ReadCastbarProvider,
            companionWrites = { "general." .. fields.enable,
                "general." .. (fields.providerMemory or (fields.backend .. "BeforeHide")) },
            customSetReason = "Coordinates the selected castbar provider, enabled state and dependent backend settings.", set = SetCastbarProvider,
            scope = unit, meta = SettingMeta(ctx, "castbar.provider", "general", fields.backend),
            beforeBind = function(widget)
                -- Player castbar ownership is independent from Player UnitFrame
                -- ownership, so the page-level frame-disabled gate must not lock this
                -- provider selector while the MSUF Player frame is off.
                widget._msuf2UnitFrameGateAlwaysEnabled = true
                W.AttachUnitEditFocus(widget, unit, "castbar")
            end,
        })
    else
        SectionNote(ctx, unit, providerCard, "providerCard", "MSUF castbar", 16, -58, rightW - 32)
    end
    local interrupt = ControlRow(ctx, generalCard, { "toggle", "interrupt", true, { "Show interrupt", 16, -84, 240 },
        get = function() return ReadBool(unit, "showInterrupt", true) end,
        write = { call = SetBool, args = { "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true } } }, --[[schema setter: UnitFrameVisuals.19]]
        scope = unit, meta = SettingMeta(ctx, "castbar.show_interrupt", unit, "showInterrupt"),
        beforeBind = s.PrepareControl,
    })
    -- Appends the interrupter's class-colored name to the Interrupted feedback
    -- (Blizzard's SPELL_INTERRUPTED_BY format); resolution is secret-safe and
    -- falls back to the plain label against restricted identities.
    local interruptSource = ControlRow(ctx, generalCard, { "toggle", "interruptSource", false, { "Show interrupter name", 16, -116, 240 },
        get = function() return ReadBool(unit, "showInterruptSource", false) end,
        write = { call = SetBool, args = { "MSUF2_CASTBAR_INTERRUPT_SOURCE", { castbar = true, preview = true } } }, --[[schema setter: UnitFrameVisuals.20]]
        scope = unit, meta = SettingMeta(ctx, "castbar.show_interrupt_source", unit, "showInterruptSource"),
        beforeBind = s.PrepareControl,
    })
    BindExactCastbarTabTarget(interruptSource, "general", tostring(unit) .. ".showInterruptSource")
    local sizeCardW = sizeCard._msuf2Width or (sectionW - 32)
    local sizeRightX = max(350, floor(sizeCardW * 0.52))
    local sizeControlWLeft = min(300, max(220, sizeRightX - 42))
    local sizeControlWRight = min(320, max(220, sizeCardW - sizeRightX - 24))
    local widthMode = ControlRow(ctx, sizeCard, { "dropdown", "widthMode", "manual", { "Width mode", CASTBAR_WIDTH_SOURCE_VALUES,
        sizeControlWLeft }, { 16, -52, sizeControlWLeft },
        get = ReadWidthSource,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
        write = { call = SetGeneralValue, keyOnly = true, convert = NormalizeWidthSource,
            accept = function() return CastbarWidthSourceKey() ~= nil end,
            args = { "MSUF2_CASTBAR_WIDTH_MODE" }, after = RefreshCastbarEnabled
        } --[[schema setter: H4.UnitFrameVisuals.21]],
        scope = unit, meta = SettingMeta(ctx, "castbar.width_mode", "general", CastbarWidthSourceKey()),
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    local widthKey = CastbarWidthKey()
    local heightKey = CastbarHeightKey()
    local defaultSize = CASTBAR_DEFAULT_SIZE[unit] or CASTBAR_DEFAULT_SIZE.target
    local function SizeSlider(id, key, default, label, lo, hi, y, reason, metaPath)
        return ControlRow(ctx, sizeCard, { "slider", id, default, { label, lo, hi, 1, sizeControlWRight }, { sizeRightX, y, sizeControlWRight },
            get = function() return ReadGeneralNumber(key, default) end,
            write = { call = SetGeneralNumber, keyOnly = true, args = { reason } }, --[[schema setter: UnitFrameVisuals.22]]
            scope = unit, meta = SettingMeta(ctx, metaPath, "general", key), roundStep = true,
            beforeBind = s.PrepareControl, castbarControl = true,
        })
    end
    local manualWidth = SizeSlider("manualWidth", widthKey, defaultSize.width, "Manual width", 40, 900, -52, "MSUF2_CASTBAR_WIDTH",
        "castbar.manual_width")
    SizeSlider("height", heightKey, defaultSize.height, "Height", 6, 80, -106, "MSUF2_CASTBAR_HEIGHT", "castbar.height")
    s.castbarNotice, s.enabled, s.provider, s.interrupt = castbarNotice, enabled, provider, interrupt
    s.manualWidth, s.defaultSize = manualWidth, defaultSize
end
function CastbarSection.IconAndText(s)
    local ctx, unit, fields, rightW, RefreshCastbarEnabled = s.ctx, s.unit, s.fields, s.rightW, s.RefreshCastbarEnabled
    local iconControls, spellControls, targetNameControls = s.iconControls, s.spellControls, s.targetNameControls
    local DetailKey, ReadGeneralValue = s.DetailKey, s.ReadGeneralValue
    local BuildDetailControls, controlWLeft, controlWRight = s.BuildDetailControls, s.controlWLeft, s.controlWRight
    local iconCard, portraitIconCard, spellCard = s.iconCard, s.portraitIconCard, s.spellCard
    local targetNameCard = s.targetNameCard
    local function BindCastbarFeatureToggle(parent, field, reason)
        local control = ControlRow(ctx, parent, { "switch", field, true, { "Enable", 16, -52, 160 },
            get = function() return ReadGeneralBool(field, true) end,
            write = { call = SetGeneralBool, keyOnly = true, args = { reason, { castbar = true, preview = true } },
                after = RefreshCastbarEnabled }, --[[schema setter: UnitFrameVisuals.23]]
            scope = unit, meta = SettingMeta(ctx, "castbar.feature." .. tostring(reason), "general", field),
            beforeBind = s.PrepareControl,
        })
        return control
    end
    local icon = BindCastbarFeatureToggle(iconCard, fields.icon, "MSUF2_CASTBAR_ICON")
    BuildDetailControls(iconCard, iconControls, {
        { "dropdown", DetailKey("IconPosition"), "LEFT", { "Position", CASTBAR_ICON_POSITIONS, min(260, controlWLeft) }, { 16, -88, min(260,
            controlWLeft) }, reason = "MSUF2_CASTBAR_ICON_POSITION" },
        { "slider", DetailKey("IconSize"), 0, { "Size", 0, 128, 1, controlWLeft }, { 16, -142, controlWLeft }, reason = "MSUF2_CASTBAR_ICON_SIZE" },
        { "slider", DetailKey("IconZoom"), 100, { "Icon Zoom (%)", 100, 200, 1, controlWLeft }, { 16, -196, controlWLeft },
            reason = "MSUF2_CASTBAR_ICON_ZOOM" },
        { "slider", DetailKey("IconSpacing"), 1, { "Spacing", 0, 40, 1, controlWLeft }, { 16, -250, controlWLeft }, reason = "MSUF2_CASTBAR_ICON_SPACING" },
        { "slider", DetailKey("IconBorderThickness"), 0, { "Border thickness", 0, 8, 1, controlWLeft }, { 16, -304, controlWLeft },
            reason = "MSUF2_CASTBAR_ICON_BORDER_THICKNESS",
            companionWrites = { "general." .. DetailKey("IconBorderStyle") }, beforeSet = function(v)
            if tonumber(v) and tonumber(v) > 0 and tostring(ReadGeneralValue(DetailKey("IconBorderStyle"), "DARK")):upper() == "NONE" then
                GetGeneral()[DetailKey("IconBorderStyle")] = "DARK"
                -- The Border style dropdown below must show what this just
                -- wrote. Only the one-shot upgrade refreshes, never every tick
                -- of the drag.
                M.RequestRefresh(ctx, "castbar-icon-border-style-upgrade")
            end
        end },
        { "dropdown", DetailKey("IconBorderStyle"), "DARK", { "Border Style", CASTBAR_ICON_BORDER_STYLES, min(260, controlWLeft) }, { 16, -358,
            min(260, controlWLeft) }, reason = "MSUF2_CASTBAR_ICON_BORDER_STYLE", afterSet = function()
                -- The Castbar Icon Border Color shortcut is relevant only for
                -- the Castbar style, so its ::: dot re-evaluates on every
                -- change here.
                M.RequestRefresh(ctx, "castbar-icon-border-style")
            end },
    })
    -- Second surface for the Portrait section's cast-icon toggle: players look for
    -- it next to the castbar icon options. Both toggles write the same per-unit key
    -- and request a page refresh, so whichever one is clicked updates the other.
    -- It stays out of allCastbarControls/iconControls on purpose - the portrait
    -- cast icon is a portrait feature and works with any castbar backend.
    local portraitCastIcon = ControlRow(ctx, portraitIconCard, { "toggle", "portraitCastIcon", false, { "Show cast spell icon in portrait", 16, -52,
        rightW - 32 },
        get = function() return ReadBool(unit, "portraitCastSpellIcon", false) end,
        write = { call = SetPortraitValue, boolean = true, args = { "MSUF2_PORTRAIT_CAST_ICON" },
            after = function() M.RequestRefresh(ctx, "portrait-cast-icon-mirror") end }, --[[schema setter: UnitFrameVisuals.24]]
        scope = unit, setting = unit .. ".portraitCastSpellIcon", meta = ReviewedMeta(ctx, "castbar.portrait_cast_icon", "setting", "duplicate",
            "Second surface for the Portrait section cast-icon toggle; that control owns the Search target for portraitCastSpellIcon."),
        beforeBind = function(widget)
            W.AttachUnitEditFocus(widget, unit, "portrait")
        end,
    })
    portraitCastIcon._msuf2SearchText = "Portrait cast spell icon casting channel empower castbar icon"
    SectionNote(ctx, unit, portraitIconCard, "portraitIconCard",
        "The same setting as Portrait > More Options. It swaps the portrait for the spell icon while the unit casts, "
        .. "so the portrait has to be enabled.", 16, -86, rightW - 32, true)
    local text = BindCastbarFeatureToggle(spellCard, fields.text, "MSUF2_CASTBAR_TEXT")
    BuildDetailControls(spellCard, spellControls, {
        { "dropdown", DetailKey("SpellNamePosition"), "LEFT", { "Position preset", CASTBAR_TEXT_POSITIONS, min(260, controlWLeft) }, { 16, -88,
            min(260, controlWLeft) }, reason = "MSUF2_CASTBAR_SPELL_POSITION" },
        { "slider", DetailKey("SpellNameFontSize"), 0, { "Size", 0, 48, 1, controlWLeft }, { 16, -142, controlWLeft }, reason = "MSUF2_CASTBAR_SPELL_SIZE" },
        -- Position owns the visible justification, matching Time Text.
        -- Spell text color deliberately lives on the Colors page (castbar
        -- detail colors) and in the per-control color shortcuts only; a second
        -- inline swatch here double-writes the same key.
    })
    local targetNameToggle
    if fields.targetName and targetNameCard then
        targetNameToggle = ControlRow(ctx, targetNameCard, { "switch", "targetNameToggle", false, { "Enable", 16, -52, 160 },
            get = function() return ReadGeneralBool(fields.targetName, false) end,
            write = { call = SetGeneralBool, keyOnly = true, args = { "MSUF2_CASTBAR_TARGET_NAME", { castbar = true, preview = true } },
                after = RefreshCastbarEnabled }, --[[schema setter: UnitFrameVisuals.25]]
            scope = unit, meta = SettingMeta(ctx, "castbar.show_target_name", "general", fields.targetName),
            beforeBind = s.PrepareControl, castbarControl = true,
        })
        BuildDetailControls(targetNameCard, targetNameControls, {
            { "dropdown", DetailKey("TargetNamePosition"), "BELOW", { "Position preset", CASTBAR_TEXT_POSITIONS, min(260, controlWRight) }, { 16, -88,
                min(260, controlWRight) }, reason = "MSUF2_CASTBAR_TARGET_NAME_POSITION" },
            { "slider", DetailKey("TargetNameFontSize"), 10, { "Size", 6, 48, 1, controlWRight }, { 16, -142, controlWRight },
                reason = "MSUF2_CASTBAR_TARGET_NAME_SIZE" },
            { "dropdown", DetailKey("TargetNameAlign"), "RIGHT", { "Alignment", CASTBAR_TEXT_ALIGN, min(260, controlWRight) }, { 16, -196, min(260,
                controlWRight) }, reason = "MSUF2_CASTBAR_TARGET_NAME_ALIGN" },
            -- Target text color deliberately lives on the Colors page (castbar
            -- detail colors) and in the per-control color shortcuts only; a second
            -- inline swatch here double-writes the same key.
        })
    end
    s.BindCastbarFeatureToggle, s.icon, s.portraitCastIcon = BindCastbarFeatureToggle, icon, portraitCastIcon
    s.text, s.targetNameToggle = text, targetNameToggle
end
function CastbarSection.Advanced(s)
    local ctx, unit, fields, rightW, RefreshCastbarEnabled = s.ctx, s.unit, s.fields, s.rightW, s.RefreshCastbarEnabled
    local iconControls, spellControls, timeControls = s.iconControls, s.spellControls, s.timeControls
    local AddControl, DetailKey, CastbarWidthKey = s.AddControl, s.DetailKey, s.CastbarWidthKey
    local ReadGeneralValue, ReadGeneralNumber = s.ReadGeneralValue, s.ReadGeneralNumber
    local SetGeneralValue, SetGeneralNumber = s.SetGeneralValue, s.SetGeneralNumber
    local BuildDetailControls, controlWLeft, controlWRight = s.BuildDetailControls, s.controlWLeft, s.controlWRight
    local timeCard, textAdvancedCard, iconAdvancedCard = s.timeCard, s.textAdvancedCard, s.iconAdvancedCard
    local layerAdvancedCard, defaultSize = s.layerAdvancedCard, s.defaultSize
    local BindCastbarFeatureToggle = s.BindCastbarFeatureToggle
    local function ReadSpellTextWidthMode()
        local value = tostring(ReadGeneralValue(DetailKey("SpellNameTruncate"), "AUTO") or "AUTO"):upper()
        if value == "CLIP" or value == "NONE" then return value end
        return "AUTO"
    end
    local function IsManualSpellTextWidth()
        return ReadSpellTextWidthMode() == "CLIP"
    end
    local function DefaultSpellTextManualWidth()
        local value = ReadGeneralNumber(CastbarWidthKey(), defaultSize.width) - 64
        return max(40, min(260, floor(value + 0.5)))
    end
    local spellTextWidthMode = ControlRow(ctx, textAdvancedCard, { "dropdown", "spellTextWidthMode", "AUTO", { "Width behavior",
        CASTBAR_TRUNCATE_VALUES, min(260, controlWLeft) }, { 16, -52, min(260, controlWLeft) },
        get = ReadSpellTextWidthMode,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            companionWrites = { "general." .. DetailKey("SpellNameMaxWidth") },
            set = function(v)
            local nextValue = tostring(v or "AUTO"):upper()
            if nextValue ~= "CLIP" and nextValue ~= "NONE" then nextValue = "AUTO" end
            SetGeneralValue(DetailKey("SpellNameTruncate"), nextValue, "MSUF2_CASTBAR_SPELL_TRUNCATE")
            if nextValue == "CLIP" and ReadGeneralNumber(DetailKey("SpellNameMaxWidth"), 0) <= 0 then
                SetGeneralNumber(DetailKey("SpellNameMaxWidth"), DefaultSpellTextManualWidth(), "MSUF2_CASTBAR_SPELL_MAX_WIDTH")
            end
            RefreshCastbarEnabled()
        end,
        -- Selecting manual width can also initialize the paired maximum width (same general root).
        scope = unit, meta = SettingMeta(ctx, "castbar.spell_text_width_mode", "general", DetailKey("SpellNameTruncate")),
        beforeBind = function(widget)
            AddControl(spellControls, widget)
            W.AttachUnitEditFocus(widget, unit, "castbar")
        end,
    })
    local spellTextManualWidth = ControlRow(ctx, textAdvancedCard, { "slider", "spellTextManualWidth", 0, { "Manual text width", 20, 500, 1,
        controlWLeft }, { 16, -106, controlWLeft },
        get = function() return ReadGeneralNumber(DetailKey("SpellNameMaxWidth"), 0) end,
        write = { call = SetGeneralNumber, keyOnly = true, args = { "MSUF2_CASTBAR_SPELL_MAX_WIDTH" } }, --[[schema setter: UnitFrameVisuals.27]]
        scope = unit, meta = SettingMeta(ctx, "castbar.spell_text_manual_width", "general", DetailKey("SpellNameMaxWidth")), roundStep = true,
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    BuildDetailControls(iconAdvancedCard, iconControls, {
        { "slider", DetailKey("IconFrameLevelOffset"), 0, { "Layer (0-30)", 0, 30, 1, controlWRight }, { 16, -52, controlWRight },
            reason = "MSUF2_CASTBAR_ICON_LAYER" },
    })
    SectionNote(ctx, unit, iconAdvancedCard, "iconAdvancedCard",
        "0 keeps the icon just above the bar and moves it together with the whole-castbar layer. "
        .. "1-30 pins the icon to that frame level on the shared layer scale, so it can be ordered in front of or behind the bar, texts, "
        .. "and other frame elements.", 16, -106, rightW - 32, true)
    local castbarLayer = ControlRow(ctx, layerAdvancedCard, { "slider", "castbarLayer", 6, { "Layer (0-30)", 0, 30, 1, controlWRight }, { 16, -52,
        controlWRight },
        get = function() return ReadGeneralNumber(DetailKey("FrameLevelOffset"), 6) end,
        write = { call = SetGeneralNumber, keyOnly = true, args = { "MSUF2_CASTBAR_LAYER" } }, --[[schema setter: UnitFrameVisuals.28]]
        scope = unit, meta = SettingMeta(ctx, "castbar.frame_layer", "general", DetailKey("FrameLevelOffset")), roundStep = true,
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    SectionNote(ctx, unit, layerAdvancedCard, "layerAdvancedCard",
        "Applies to the entire castbar: bar, icon, all text, effects, and border. "
        .. "All MSUF elements share this 0-30 order; every part of layer 30 draws above every part of layer 29.",
        16, -108, rightW - 32, true)
    local time = BindCastbarFeatureToggle(timeCard, fields.time, "MSUF2_CASTBAR_TIME")
    BuildDetailControls(timeCard, timeControls, {
        { "dropdown", fields.timeFormat, "CURRENT", { "Format", CASTBAR_TIME_FORMATS, min(260, controlWLeft) }, { 16, -88, min(260, controlWLeft) },
            reason = "MSUF2_CASTBAR_TIME_FORMAT" },
        { "dropdown", DetailKey("TimePosition"), "RIGHT", { "Position preset", CASTBAR_TEXT_POSITIONS, min(260, controlWLeft) }, { 16, -142,
            min(260, controlWLeft) }, reason = "MSUF2_CASTBAR_TIME_POSITION" },
        { "slider", DetailKey("TimeFontSize"), 0, { "Size", 0, 48, 1, controlWLeft }, { 16, -196, controlWLeft }, reason = "MSUF2_CASTBAR_TIME_SIZE" },
        -- Cast time color deliberately lives on the Colors page (castbar
        -- detail colors) and in the per-control color shortcuts only; a second
        -- inline swatch here double-writes the same key.
    })
    s.IsManualSpellTextWidth, s.spellTextManualWidth, s.time = IsManualSpellTextWidth, spellTextManualWidth, time
end
local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", CastbarTabHeight(unit, CurrentCastbarTab(unit)), false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local leftW = floor((sectionW - 48 - cardGap) * 0.5)
    leftW = max(310, min(430, leftW))
    local rightX = leftX + leftW + cardGap
    local rightW = max(310, min(430, sectionW - rightX - 16))
    local prefix = CASTBAR_PREFIX[unit]
    local RefreshCastbarEnabled = M.RefreshProxy()
    local canUseBlizzardProvider = (unit == "player")
    local allCastbarControls, iconControls, spellControls, targetNameControls, timeControls = {}, {}, {}, {}, {}
    local s = {
        ctx = ctx, builder = builder, unit = unit, fields = fields, sec = sec, sectionW = sectionW, leftX = leftX,
        cardGap = cardGap, leftW = leftW, rightX = rightX, rightW = rightW, prefix = prefix,
        RefreshCastbarEnabled = RefreshCastbarEnabled, canUseBlizzardProvider = canUseBlizzardProvider,
        allCastbarControls = allCastbarControls, iconControls = iconControls, spellControls = spellControls,
        targetNameControls = targetNameControls, timeControls = timeControls,
    }
    CastbarSection.Binders(s)
    CastbarSection.Cards(s)
    CastbarSection.Tabs(s)
    CastbarSection.General(s)
    CastbarSection.IconAndText(s)
    CastbarSection.Advanced(s)
    local ReadWidthSource, ReadCastbarBackend, castbarNotice = s.ReadWidthSource, s.ReadCastbarBackend, s.castbarNotice
    local enabled, provider, interrupt, manualWidth, icon = s.enabled, s.provider, s.interrupt, s.manualWidth, s.icon
    local portraitCastIcon, text, targetNameToggle = s.portraitCastIcon, s.text, s.targetNameToggle
    local IsManualSpellTextWidth, spellTextManualWidth, time = s.IsManualSpellTextWidth, s.spellTextManualWidth, s.time
    local castbarFeatureToggles = { time, interrupt, icon, text, targetNameToggle }
    local function MsufOn() return ReadCastbarBackend() == "MSUF" end
    -- Hover reason for the locked castbar controls: the section notice wording.
    local function BackendReason()
        local backend = ReadCastbarBackend()
        if backend == "MSUF" then return nil end
        if backend == "HIDE" then return M.Format("%s castbar is off. Turn it on to use the MSUF castbar.", UnitTopLabel(unit)) end
        return M.Format("%s castbar uses Blizzard. Select MSUF to adjust castbar layout and text behavior.", UnitTopLabel(unit))
    end
    RefreshCastbarEnabled = RefreshCastbarEnabled(M.BindGateGroup(ctx, nil, {
        { enable = { enabled }, controls = castbarFeatureToggles, on = MsufOn, reason = BackendReason },
        { controls = provider, when = function() return provider ~= nil end, on = function() return ReadCastbarBackend() ~= "HIDE" end,
            reason = BackendReason },
        { controls = allCastbarControls, on = MsufOn, reason = BackendReason },
        { controls = manualWidth, on = function() return MsufOn() and ReadWidthSource() == "manual" end },
        { controls = iconControls, on = function() return MsufOn() and ReadGeneralBool(fields.icon, true) end },
        { controls = spellControls, on = function() return MsufOn() and ReadGeneralBool(fields.text, true) end },
        { controls = targetNameControls, on = function() return MsufOn() and fields.targetName and ReadGeneralBool(fields.targetName, false) end },
        { controls = spellTextManualWidth, on = function() return MsufOn() and ReadGeneralBool(fields.text, true) and IsManualSpellTextWidth() end },
        { controls = timeControls, on = function() return MsufOn() and ReadGeneralBool(fields.time, true) end },
        -- Mirrored portrait setting: gated by the portrait, never by the castbar.
        { controls = portraitCastIcon, on = function() return NormalizePortrait(unit) ~= "OFF" end },
    }, {
        also = function()
            local backend = ReadCastbarBackend()
            if backend ~= "MSUF" then
                if backend == "HIDE" then
                    castbarNotice:SetMessage(M.Format("%s castbar is off. Turn it on to use the MSUF castbar.", UnitTopLabel(unit)), "warning")
                else
                    castbarNotice:SetMessage(M.Format("%s castbar uses Blizzard. Select MSUF to adjust castbar layout and text behavior.",
                        UnitTopLabel(unit)), "warning")
                end
                castbarNotice:Show()
            else
                castbarNotice:Hide()
            end
            SetSectionHeaderStatus(sec, nil)
        end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end

return BuildCastbar, PrepareCastbarSwitch, CastbarTabHeight, CurrentCastbarTab
end
