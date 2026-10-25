local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Core functions this page calls by their global names: required here at load.
M.RequireGlobals(FILE, {
    "MSUF_ShowReloadRecommendedPopup",
    "MSUF_ApplyRoundedUnitframes",
})
-- Resolved once at load, so the value and refresh paths that call them (setters, the apply
-- request, the anchor refresh) never resolve a name.
local Core = {
    ShowReloadPopup = MSUF.Require("MSUF_ShowReloadRecommendedPopup", FILE),
    ApplyRounded = MSUF.Require("MSUF_ApplyRoundedUnitframes", FILE),
    ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE),
    AutomaticProvider = MSUF.Require("MSUF_GetAutomaticCooldownAnchorProvider", FILE),
    CooldownEnabled = MSUF.Require("MSUF_IsCooldownAnchorEnabled", FILE),
    SetCooldownEnabled = MSUF.Require("MSUF_SetCooldownAnchorEnabled", FILE),
}
local EnsureDB = M.EnsureDB
local C_Timer = M.MenuTimer or C_Timer

-- Shared Unit page sections.
-- Builds reusable controls for per-unit basics, load rules, target-of-target text behavior,
-- and copy/edit-mode actions. Runtime ownership stays in UnitFrames and EditMode modules.
local W = M.Widgets
local T = M.Theme
local SetControlsEnabled = W.SetControlsEnabled
local ControlGates = M.ControlGates or {}
local UP = M.UnitPage or {}
local floor = math.floor
local max, min = math.max, math.min
local VT = M.ValueTextList
local UNIT_PAGES, LOAD_CONDITIONS, BOSS_LAYOUT_OPTIONS = UP.UNIT_PAGES or {}, UP.LOAD_CONDITIONS or {}, UP.BOSS_LAYOUT_OPTIONS or {}
local SEPARATORS, UF_COPY_CATEGORIES = UP.SEPARATORS or {}, UP.UF_COPY_CATEGORIES or {}
local GetConf, GetGeneral, DefaultCopyTarget, UnitTopLabel = UP.GetConf, UP.GetGeneral, UP.DefaultCopyTarget, UP.UnitTopLabel
local UnitTopLabelKey = UP.UnitTopLabelKey
local UnitTopPillWidth, NewCopyScopeDefaults, ConfirmCopyToAll = UP.UnitTopPillWidth, UP.NewCopyScopeDefaults, UP.ConfirmCopyToAll
local CopyUnitSettings, ReadBool = UP.CopyUnitSettings, UP.ReadBool
local SetBool, ReadNumber = UP.SetBool, UP.ReadNumber
local SetControlEnabled, NormalizeBossLayoutMode, UpdateLoadActive = UP.SetControlEnabled, UP.NormalizeBossLayoutMode, UP.UpdateLoadActive
local SettingMeta, RegisterControl = UP.SettingMeta, UP.RegisterControl
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
-- Lazy shells declare their header before the body builds, as the pilot sections do.
local function DeclareSection(_, section, unit) Schema.Section(section, unit) end
-- Hover options the Basics and Visibility tips share (AddTooltip only reads them).
local TIP_OPTS = { hook = true, owner = "ANCHOR_RIGHT" }
local UNIT_ANCHOR_SECTION_HEIGHT = 306
local UNIT_AURAS_MENU_UNITS = M.KeySetFromWords "player pet target focus boss arena"
local HEALTH_COLOR_GLOBAL = "GLOBAL"
local HEALTH_COLOR_LABELS = {
    class = "Class / Reaction",
    gradient = "Health Gradient",
    unified = "Unified Color",
    dark = "Dark Mode",
}
local HEALTH_COLOR_ALIASES = {}
local HEALTH_COLOR_OPTIONS = { { value = HEALTH_COLOR_GLOBAL, text = "Use Global" } }
for _, mode in ipairs({ "class", "gradient", "unified", "dark" }) do
    HEALTH_COLOR_ALIASES[mode], HEALTH_COLOR_ALIASES[mode:upper()] = mode, mode
    HEALTH_COLOR_OPTIONS[#HEALTH_COLOR_OPTIONS + 1] = { value = mode, text = HEALTH_COLOR_LABELS[mode] }
end
-- Fill Direction merges the fill axis (verticalFillBars) with the in-axis
-- direction (reverseFillBars) into one control. Compiled by CompileUnitHealth/
-- CompileUnitPower (MSUF_UF_Config.lua) and applied via the SetOrientation +
-- SetReverseFill blocks in the Health/Power elements.
local FILL_DIRECTION_OPTIONS = {
    { value = "lr", text = "Left to Right" },
    { value = "rl", text = "Right to Left" },
    { value = "bt", text = "Bottom to Top" },
    { value = "tb", text = "Top to Bottom" },
}
local FILL_DIRECTION_STATE = {
    lr = { reverse = false, vertical = false },
    rl = { reverse = true,  vertical = false },
    bt = { reverse = false, vertical = true  },
    tb = { reverse = true,  vertical = true  },
}
local function FillDirectionValue(reverse, vertical)
    if vertical then return reverse and "tb" or "bt" end
    return reverse and "rl" or "lr"
end

local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }
local ENABLED_HEADER_BG = { 0.060, 0.070, 0.130, 0.48 }
local TINTED_ENABLED_HEADER_BG = { 0, 0, 0, 0.48 }
local function EnabledHeaderColor()
    if T.classicAtlas or T.menuAppearancePreset == "midnightDark"
        or (T.MenuAccentSurfacesTinted and T.MenuAccentSurfacesTinted()) then
        local color = T.colors and T.colors.coreSurface
        if color then
            TINTED_ENABLED_HEADER_BG[1] = color[1]
            TINTED_ENABLED_HEADER_BG[2] = color[2]
            TINTED_ENABLED_HEADER_BG[3] = color[3]
            return TINTED_ENABLED_HEADER_BG
        end
    end
    return ENABLED_HEADER_BG
end


local function RequestUnitRuntimeApply(unit, reason, opts, flushNow)
    opts = opts or {}
    opts.history = false
    if M and type(M.RequestUnitDomains) == "function" then
        local ok = M.RequestUnitDomains(unit, reason or "MSUF2_UNIT_SECTION", opts) ~= false
        if ok and flushNow then Core.ApplyService.Flush() end
        return ok
    end
    Core.ApplyService.RequestUnitDomains(unit, reason or "MSUF2_UNIT_SECTION", opts)
    if flushNow then Core.ApplyService.Flush() end
    return true
end
local UnitSectionShared = M.UnitSectionsShared or {}
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus

local BuildPreview, BuildTopActions, ApplyUnitFrameEnabledGate, Preview, UNIT_TAB_ORDER, UNIT_PAGE_FOR_UNIT, UnitFrameEnabled,
    SectionNumber = M.UnitSectionFactories.Page(
    MSUF, M, FILE, PixelLayoutRegion, Core, C_Timer, W, T, ControlGates, UP, floor, max, UNIT_PAGES, UF_COPY_CATEGORIES,
    DefaultCopyTarget, UnitTopLabel, UnitTopLabelKey, UnitTopPillWidth, NewCopyScopeDefaults, ConfirmCopyToAll, CopyUnitSettings,
    ReadBool, RegisterControl, Schema, RequestUnitRuntimeApply, UnitSectionShared
)
local BuildLayout, BuildInlineText, BuildStatus, BuildLoadConditions, BuildBossLayout, BuildBossTargetHighlight, BuildArenaLayout,
    NormalizeHealthColorMode, GlobalHealthColorMode, HealthColorModeOptions = M.UnitSectionFactories.Layout(
    { EnsureDB = EnsureDB, GetConf = GetConf, GetGeneral = GetGeneral, ReadBool = ReadBool, ReadNumber = ReadNumber,
        NormalizeBossLayoutMode = NormalizeBossLayoutMode, UpdateLoadActive = UpdateLoadActive },
    { Widgets = W, Theme = T, Schema = Schema, SetControlEnabled = SetControlEnabled, SettingMeta = SettingMeta,
        RegisterControl = RegisterControl, UnitOptions = ROW_OPTIONS, TooltipOptions = TIP_OPTS, Shared = UnitSectionShared },
    { PixelLayoutRegion = PixelLayoutRegion, LoadConditions = LOAD_CONDITIONS, BossLayouts = BOSS_LAYOUT_OPTIONS,
        Separators = SEPARATORS, AnchorSectionHeight = UNIT_ANCHOR_SECTION_HEIGHT },
    { Global = HEALTH_COLOR_GLOBAL, Labels = HEALTH_COLOR_LABELS, Aliases = HEALTH_COLOR_ALIASES, Options = HEALTH_COLOR_OPTIONS },
    { Core = Core, RequestUnitApply = RequestUnitRuntimeApply }
)

local function UnitSectionUX(unit)
    local fields = UP.SectionFields or {}
    local sections = {
        -- frameBarShape has no Basics control any more, but the rounded surface still
        -- honours a stored ROUNDED/SQUARE; Reset section is the way to clear it.
        frame_basics = { fields = "smoothFill chunkedFill reverseFillBars verticalFillBars healthColorMode frameBarShape", summary = function(c)
            return SectionNumber(c.width, 220) .. " x " .. SectionNumber(c.height, 40) .. " px"
        end },
        portrait = { fields = fields.portrait, copy = "portrait" },
        power_bar = { fields = fields.power_bar, copy = "power" },
        text = { fields = fields.text, copy = "text" },
        auras = { summary = function()
            local model = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
            if not (model and model.ReadNumber) then return "" end
            return M.Tr("Buffs") .. " " .. SectionNumber(model.ReadNumber(unit, "maxBuffs", 8, 0, 80))
                .. " / " .. M.Tr("Debuffs") .. " " .. SectionNumber(model.ReadNumber(unit, "maxDebuffs", 12, 0, 80))
        end },
        castbar = { copy = "castbar", canCopy = function(a, b) return UP.CASTBAR_FIELDS[a] and UP.CASTBAR_FIELDS[b] end },
        unit_dispel_overlay = { prefixes = "unitDispelOverlay" },
        unit_dispel_symbol = { prefixes = "unitDispelSymbol" },
        -- Arena only (Pages/MSUF_Menu2_UnitArenaTrinket.lua): reset, no copy target.
        pvp_trinket = { fields = UP.ARENA_TRINKET_FIELDS, noCopy = true },
        transparency = { fields = fields.transparency, copy = "transparency", summary = function(c) return SectionNumber((c.hpBarAlpha
            or 1) * 100) .. "%" end },
        load_conditions = { fields = fields.load_conditions, copy = "load", summary = function(c)
            local count = 0
            for key, value in pairs(c) do if key:find("loadCond", 1, true) == 1 and key ~= "loadCondActive" and value == true then count = count + 1 end end
            return count > 0 and M.Format("%d active conditions", count) or ""
        end },
        texture_layer = { fields = fields.texture_layer, copy = "texlayer", summary = function(c)
            local n = (c.texLayerEnabled and 1 or 0) + (c.texLayer2Enabled and 1 or 0) + (c.texLayer3Enabled and 1 or 0)
            return n > 0 and M.Format("%d / 3 textures enabled", n) or ""
        end },
        anchoring = { fields = "point relativePoint offsetX offsetY anchorFrameName anchorToUnitframe", noCopy = true },
    }
    -- The same frames as the unit tabs, so a client never offers a frame it cannot show.
    local targets = {}
    for _, key in ipairs(UNIT_TAB_ORDER) do
        if UNIT_PAGE_FOR_UNIT[key] and (not M.SupportsFrameScope or M.SupportsFrameScope(key)) then
            targets[#targets + 1] = { value = key, text = UnitTopLabelKey(key) }
        end
    end
    return {
        sections = sections, targets = targets, scope = function() return unit end, conf = GetConf, label = UnitTopLabel,
        targetOff = function(key) return not UnitFrameEnabled(key) end,
        defaults = function(scope)
            local defaults = UnitSectionShared.FactoryProfile()
            -- Optional units can be absent from the factory snapshot. Clearing
            -- their overrides restores the same inherited defaults as page reset.
            return type(defaults) == "table" and (defaults[scope] or {}) or nil
        end,
        copy = function(source, target, category) return CopyUnitSettings(source, target, { [category] = true }) end,
        apply = function(scope, id)
            if id == "load_conditions" then UpdateLoadActive(scope) end
            M.RequestUnitDomains(scope, "MSUF2_SECTION_RESET", { preview = true, text = true, fonts = true, power = true, alpha = true })
            -- The frame bar shape decides whether the rounded runtime runs at all.
            if id == "frame_basics" then Core.ApplyRounded() end
        end,
    }
end
local function PrepareBasicsSwitch(ctx, sec, unit)
    Schema.Section(sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local enable = Schema.Build(ctx, sec, {
        { "sectionSwitch", "enabled", true, { "Enable", "Enable" },
            beforeBind = function(widget)
                widget._msuf2UnitFrameGateAlwaysEnabled = true
            end,
            get = function() return ReadBool(unit, "enabled", true) end,
            write = { call = SetBool, args = { "MSUF2_FRAME_ENABLED", { preview = true } }, after = function() M.Refresh(ctx) end },
                --[[schema setter: UnitSections.1]]
            meta = SettingMeta(ctx, "basics.enabled", unit, "enabled"), scope = unit,
        }
    }, ROW_OPTIONS).enabled
    enable:SetChecked(ReadBool(unit, "enabled", true))
    return enable
end
local function AttachBasicsHeaderStatus(sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if not entry then return end
    local function Refresh()
        local enabled = ReadBool(unit, "enabled", true)
            and (unit ~= "focustarget" or ReadBool("focus", "enabled", true))
        local color = enabled and EnabledHeaderColor() or WARNING_HEADER_BG
        W.SetCollapsibleHeaderBaseTone(entry, color, color[4])
        T.SetTranslatedText(entry.label, M.Tr("Basics") .. (enabled and "" or (" - " .. M.Tr("Frame disabled"))))
    end
    Refresh()
    return Refresh
end
local function BuildBasicsColorRows(ctx, sec, unit, colW, gap, x1, x2, x3, labelW)
    local colorW = math.min(270, math.max(220, colW * 2))
    -- Fill Direction shares the Health Color Scheme row so the section stays within its
    -- declared height instead of overlapping the next accordion header. Snap to
    -- the column grid when there is room, otherwise sit just right of the
    -- width-capped Health Color Scheme dropdown; clamp the width so it never
    -- runs into the third column (Pet keeps its class-color toggle there).
    local fillDirW = colorW
    local fillDirX = math.max(x2, x1 + fillDirW + gap)
    local fillDirFit = (x3 - gap) - fillDirX
    if fillDirFit > 0 and fillDirW > fillDirFit then fillDirW = fillDirFit end
    local rows = {
        { "dropdown", "healthColorMode", HEALTH_COLOR_GLOBAL, { "Health Color Scheme", HealthColorModeOptions, colorW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, x1, -116, colorW)
            end,
            get = function()
                return NormalizeHealthColorMode(GetConf(unit).healthColorMode) or HEALTH_COLOR_GLOBAL
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", write = {
                source = function() return GetConf(unit) end, convert = NormalizeHealthColorMode,
                after = function()
                    M.RequestUnitDomains(unit, "MSUF2_HEALTH_COLOR_MODE", { preview = true, colors = true })
                    if M.Refresh then M.Refresh(ctx) end
                end
            } --[[schema setter: H4.UnitSections.1]],
            tip = { "Health Color Scheme",
                "Use Global follows the Unitframe Global Coloring mode from Colors. Other choices override only this frame.",
                TIP_OPTS },
            meta = SettingMeta(ctx, "basics.health_color_mode", unit, "healthColorMode"), scope = unit,
        },
        { "dropdown", "verticalFillBars", "lr", { "Fill Direction", FILL_DIRECTION_OPTIONS, fillDirW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, fillDirX, -116, fillDirW)
            end,
            get = function()
                return FillDirectionValue(ReadBool(unit, "reverseFillBars", false), ReadBool(unit, "verticalFillBars", false))
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { unit .. ".reverseFillBars" },
            set = function(v)
                local state = FILL_DIRECTION_STATE[v] or FILL_DIRECTION_STATE.lr
                -- Write both booleans, then a single apply/preview (mirrors the
                -- Health Color Scheme setter) so a 4-way change never double-applies.
                local conf = GetConf(unit)
                conf.reverseFillBars = state.reverse
                conf.verticalFillBars = state.vertical
                M.RequestUnitDomains(unit, "MSUF2_FILL_DIRECTION", { preview = true })
                if M.Refresh then M.Refresh(ctx) end
            end,
            tip = { "Fill Direction",
                "Axis and direction the Health and Power bars fill. Vertical options fill bottom-to-top or top-to-bottom; combines with Smooth fill.",
                TIP_OPTS },
            meta = SettingMeta(ctx, "basics.fill_direction", unit, "verticalFillBars"), scope = unit,
        },
    }
    if unit == "pet" then
        rows[#rows + 1] = { "toggle", "petFrameUsePlayerClassColor", false, { "Player Class Color", x3, -116, labelW },
            get = function() return GetGeneral().petFrameUsePlayerClassColor == true end,
            write = { source = GetGeneral, boolean = true, after = function()
                    M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
                    if M.Refresh then M.Refresh(ctx) end
                end } --[[schema setter: UnitSections.4]],
            tip = { "Use player's class color for Pet Frame",
                "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", TIP_OPTS },
            meta = SettingMeta(ctx, "basics.use_player_class_color", "general", "petFrameUsePlayerClassColor"), scope = unit,
        }
    end
    local controls = Schema.Build(ctx, sec, rows, ROW_OPTIONS)
    return controls.healthColorMode, controls.verticalFillBars, controls.petFrameUsePlayerClassColor
end
-- The Basics ::: lists the colors the frame's effective Health Color Scheme paints with.
local function AttachBasicsColorReferences(sec, unit)
    if not W.AttachContextColorReferences then return end
    local function EffectiveHealthMode()
        return NormalizeHealthColorMode(GetConf(unit).healthColorMode) or GlobalHealthColorMode()
    end
    W.AttachContextColorReferences(sec, function()
        local mode = EffectiveHealthMode()
        local refs = {}
        local general = GetGeneral()
        if mode == "gradient" then
            refs = { "health.gradient.low", "health.gradient.mid", "health.gradient.high" }
        elseif mode == "unified" then
            refs = { "health.unified" }
        elseif mode == "class" then
            if unit == "pet" and general.petFrameUsePlayerClassColor == true then
                refs = { "unit.class.current" }
            else
                refs = { unit == "pet" and "unit.pet" or "health.current" }
            end
        end
        refs[#refs + 1] = "health.background.current"
        refs[#refs + 1] = "bar.health_loss"
        return refs
    end, {
        title = M.Format("%s Health Colors", UnitTopLabel(unit)),
        note = "Colors follow this frame's effective Health Color Scheme.",
        historySource = "menu:unit-frame-basics-health-colors",
        maxTargets = 7,
        context = function()
            local context = { unit = unit, healthMode = EffectiveHealthMode() }
            if unit == "pet" and GetGeneral().petFrameUsePlayerClassColor == true and type(UnitClass) == "function" then
                local _, token = UnitClass("player")
                context.classToken = token
            end
            return context
        end,
    })
end
local function BuildBasics(ctx, builder, unit, label)
    -- Default-open so the page greets users with real settings instead of a
    -- stack of closed headers; saved accordion state still wins afterwards.
    -- Leave a full footer gutter below the disabled-frame notice. The next
    -- accordion header is created later and can otherwise cover the notice's
    -- lower edge at some UI scales.
    local sec = Schema.Section(builder:CollapsibleSection("frame_basics", "Basics", 272, true), unit)
    AttachBasicsColorReferences(sec, unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42
    local enable = PrepareBasicsSwitch(ctx, sec, unit)
    -- Fill Direction (axis + in-axis direction) is a 4-way dropdown placed on
    -- its own row below Health Color Scheme; Smooth takes the freed x2 slot.
    local basics = Schema.Build(ctx, sec, {
        { "toggle", "smoothFill", false, { "Smooth fill", x1, row1, labelW },
            get = function() return ReadBool(unit, "smoothFill", false) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            companionWrites = { unit .. ".chunkedFill" },
            set = function(v)
                UnitSectionShared.SetFillMode(ctx, unit, "health", "smoothFill", "chunkedFill", v, "MSUF2_SMOOTH_FILL",
                    "Smooth health fill", { preview = true })
            end,
            meta = SettingMeta(ctx, "basics.smooth_fill", unit, "smoothFill"), scope = unit,
        },
        { "toggle", "chunkedFill", false, { "Chunked health loss", x2, row1, labelW },
            get = function() return ReadBool(unit, "chunkedFill", false) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            companionWrites = { unit .. ".smoothFill" },
            set = function(v)
                UnitSectionShared.SetFillMode(ctx, unit, "health", "chunkedFill", "smoothFill", v, "MSUF2_CHUNKED_FILL",
                    "Chunked health loss", { preview = true })
            end,
            meta = SettingMeta(ctx, "basics.chunked_fill", unit, "chunkedFill"), scope = unit,
        },
        { "switch", "useBlizzardFrame", false, { "Force Blizzard frame on", x1, -76, math.max(196, colW + 24) },
            beforeBind = function(widget)
                widget._msuf2UnitFrameGateAlwaysEnabled = true
            end,
            get = function() return ReadBool(unit, "useBlizzardFrame", false) end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", write = { call = SetBool,
                accept = function(v)
                    return unit ~= "pettarget" and ReadBool(unit, "useBlizzardFrame", false) ~= (v == true)
                end,
                args = { "MSUF2_BLIZZARD_FRAME_OWNERSHIP", { preview = false } },
                after = function()
                    Core.ShowReloadPopup(M.Format("%s Blizzard frame ownership", label or UnitTopLabel(unit)))
                end
            } --[[schema setter: H4.UnitSections.5]],
            meta = SettingMeta(ctx, "basics.force_blizzard_frame", unit, "useBlizzardFrame"), scope = unit,
        }
    }, ROW_OPTIONS)
    local smooth, chunked, blizzard = basics.smoothFill, basics.chunkedFill, basics.useBlizzardFrame
    local blizzardHint = "Independent from MSUF Enable; /reload required."
    if unit == "pettarget" then
        blizzardHint = "Blizzard has no native Pet Target frame."
    elseif unit == "targettarget" then
        blizzardHint = "Also keeps Blizzard Target visible; /reload required."
    elseif unit == "focustarget" then
        blizzardHint = "Also keeps Blizzard Focus visible; /reload required."
    end
    Schema.Build(ctx, sec, { { "text", "unit.note.1", nil, { blizzardHint, x2, -80, math.max(190, sectionW - x2 - 14), T.colors.muted } } })
    if M.AddTooltip then
        local tooltip = M.Format("Keeps Blizzard's native frame active independently of the MSUF frame. Leave MSUF Enable on to show both, or turn " ..
            "MSUF Enable off to use only Blizzard. A UI reload is required.")
        if unit == "targettarget" then
            tooltip = tooltip .. " " .. M.Format("Blizzard Target of Target is a child of Blizzard Target, so both native frames must remain active.")
        elseif unit == "focustarget" then
            tooltip = tooltip .. " " .. M.Format("Blizzard Focus Target is a child of Blizzard Focus, so both native frames must remain active.")
        end
        if unit == "pettarget" then tooltip = M.Format("Blizzard has no native Pet Target frame.") end
        M.AddTooltip(blizzard, "Force Blizzard frame on", tooltip, TIP_OPTS)
    end
    local colorMode, fillDir, petPlayerClassColor = BuildBasicsColorRows(ctx, sec, unit, colW, gap, x1, x2, x3, labelW)
    if W.AttachUnitEditFocus then
        for _, control in ipairs({ enable, smooth, chunked, blizzard, colorMode, fillDir, petPlayerClassColor }) do
            W.AttachUnitEditFocus(control, unit, "frame")
        end
    end
    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    local RefreshBasicsState = AttachBasicsHeaderStatus(sec, unit)
    if sectionEntry then sectionEntry._msuf2RefreshState = RefreshBasicsState end
    local unitLabel = label or UnitTopLabel(unit)
    local notice, _, enableNow = UnitSectionShared.CreateSectionNotice(sec, -180, "Enable", 92)
    local enableShortcutMeta
    if unit ~= "focustarget" then
        enableShortcutMeta = {
            settingKey = unit .. ".enabled",
            command = {
                kind = "toggle", valueKind = "boolean",
                get = function() return ReadBool(unit, "enabled", true) end,
                customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
                    write = { virtual = true,
                        call = SetBool, strictBoolean = true,
                        args = { "MSUF2_FRAME_ENABLED", { preview = true } }
                    } --[[schema setter: H4.UnitSections.6]],
            },
        }
    else
        enableShortcutMeta = {
            actionKey = "enable_focus_target_frame",
        }
    end
    RegisterControl(enableNow, ctx, "basics.enable_now", "Enable", "button",
        unit ~= "focustarget" and "setting" or "action", enableShortcutMeta)
    notice:SetMessage(M.Format("%s frame is disabled and will not appear.", unitLabel), "warning")
    enableNow:SetScript("OnClick", function()
        if unit == "focustarget" and not ReadBool("focus", "enabled", true) then
            SetBool("focus", "enabled", true, "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true })
        end
        SetBool(unit, "enabled", true, "MSUF2_FRAME_ENABLED", { preview = true })
        M.RequestOrRefresh(ctx, "frame-basics-enable-now")
    end)
    Schema.Owned(enableNow, unit, "unit")
    notice:Hide()
    local basicsDependentControls = { smooth, chunked, colorMode, fillDir }
    if W.SetControlsDisabledReason then
        W.SetControlsDisabledReason(basicsDependentControls, function() return UP.FrameDisabledReason(unit) end)
    end
    local function RefreshBasicsEnabled()
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        SetControlEnabled(enable, true)
        SetControlEnabled(blizzard, unit ~= "pettarget")
        SetControlsEnabled(basicsDependentControls, ownOn)
        if parentOff then
            notice:SetMessage(M.Tr("Focus Target follows the Focus frame. Enable Focus to show it."), "warning")
            if enableNow.SetText then enableNow:SetText("Enable Focus") end
        else
            notice:SetMessage(M.Format("%s frame is disabled and will not appear.", unitLabel), "warning")
            if enableNow.SetText then enableNow:SetText("Enable") end
        end
        notice:SetShown(not ownOn or parentOff)
        RefreshBasicsState()
    end
    M.TrackRefresh(ctx, RefreshBasicsEnabled)
end
-- Anchor section sources and rules, per unit rather than per build.
local function LazySection(ctx, builder, unit, buildFn, sectionId, title, height, prepareShell)
    if not UP.BuildSectionLazy then return buildFn(ctx, builder, unit) end
    return UP.BuildSectionLazy(ctx, builder, unit, {
        sectionId = sectionId,
        title = title,
        height = height,
        prepareShell = prepareShell or DeclareSection,
        build = buildFn,
    })
end
local function PrepareBasicsShell(ctx, sec, unit)
    PrepareBasicsSwitch(ctx, sec, unit)
    local refresh = AttachBasicsHeaderStatus(sec, unit)
    if refresh then
        if M.AddRefresherOnce then
            M.AddRefresherOnce(ctx, "frame-basics-header:" .. tostring(unit), refresh)
        else
            M.AddRefresher(ctx, refresh)
        end
    end
    return refresh
end
-- Boss and Arena keep their stacked-frame page preview alive only while the page is showing.
Preview.pages = {
    boss = { key = "uf_boss", request = "RequestBossPagePreviewForKey", set = "SetBossPagePreviewActive" },
    arena = { key = "uf_arena", request = "RequestArenaPagePreviewForKey", set = "SetArenaPagePreviewActive" },
}
local function BuildUnitPage(info)
    return function(ctx)
        local unit = info.unit
        local sectionUX = UnitSectionUX(unit)
        local pagePreview = Preview.pages[unit]
        if pagePreview and ctx and ctx.wrapper then Preview.TrackPage(ctx, pagePreview) end
        local builder = W.PageBuilder(ctx)
        BuildTopActions(ctx, builder, unit, info.label)
        BuildPreview(ctx, builder, unit)
        LazySection(ctx, builder, unit, function(lazyCtx, lazyBuilder, lazyUnit)
            return BuildBasics(lazyCtx, lazyBuilder, lazyUnit, info.label)
        end, "frame_basics", "Basics", 216, PrepareBasicsShell)
        LazySection(ctx, builder, unit, BuildLayout, "anchoring", "Anchor", UNIT_ANCHOR_SECTION_HEIGHT)
        if UNIT_AURAS_MENU_UNITS[unit] and type(M.BuildAuras3UnitSection) == "function" then
            -- This workspace owns nested Buff/Debuff/Custom sections and previews;
            -- the lazy one-section proxy would stack those sections into one body.
            M.BuildAuras3UnitSection(ctx, builder, unit, sectionUX)
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, unit, "after_auras", sectionUX) end
        if unit == "target" then
            LazySection(ctx, builder, unit, BuildInlineText, "inline_text", "Inline Text", 214)
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, unit, "after_inline_text", sectionUX) end
        BuildStatus(ctx, builder, unit)
        if unit == "boss" then
            LazySection(ctx, builder, unit, BuildBossLayout, "boss_layout", "Boss Layout", 150)
            LazySection(ctx, builder, unit, BuildBossTargetHighlight, "boss_target_highlight", "Boss target highlight", 450)
        end
        if unit == "arena" then
            LazySection(ctx, builder, unit, BuildArenaLayout, "arena_layout", "Arena Layout", 160)
        end
        LazySection(ctx, builder, unit, BuildLoadConditions, "load_conditions", "Visibility", 210)
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, unit, "after_load_conditions", sectionUX) end
        UnitSectionShared.AttachSectionUX(ctx, sectionUX)
        M.TrackRefresh(ctx, function()
            ApplyUnitFrameEnabledGate(ctx, unit)
        end)
        if builder.RelayoutCollapsibles then builder:RelayoutCollapsibles() end
        ctx:SetContentHeight(math.abs(builder.y) + 42)
    end
end
-- The aura workspace's container tab and tool are the unit page's declared
-- views: a selector click shows that view's cached entry or builds it once.
local UNIT_AURA_VIEW_STATE = { unitAuraTabSelection = true, unitAuraToolSelection = true }
local function UnitAuraViewKey(unit)
    if not UNIT_AURAS_MENU_UNITS[unit] then return nil end
    return function()
        local view = M.UnitAuraWorkspaceView
        return view and view(unit) or nil
    end
end
for key, info in pairs(UNIT_PAGES) do
    local variantKey = UnitAuraViewKey(info.unit)
    M.RegisterPage(key, {
        title = info.title,
        build = BuildUnitPage(info),
        version = 29,
        variantKey = variantKey,
        viewStateKeys = variantKey and UNIT_AURA_VIEW_STATE or nil,
    })
end
