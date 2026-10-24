local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.GetMenu2Namespace()
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua"

-- Menu2 Group Bars page.
-- Builds party/raid health, power, range, dispel overlay, and text controls for the selected
-- group scope. Applies are queued through GroupPage helpers to respect secure header runtime.
local W = M.Widgets
local Schema = M.ControlSchema
local GROUP_OPTIONS = Schema.GroupOptions()
local T = M.Theme
local GP = M.GroupPage or {}
local UnitSectionShared = M.UnitSectionsShared or {}
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local DISPEL_OVERLAY_121_PTR_DISABLED = false
local TEXT_MODES = GP.TEXT_MODES or {}
local DELIMITER_VALUES, ANCHORS = GP.DELIMITER_VALUES or {}, GP.ANCHORS or {}
local DISPEL_OVERLAY_STYLES, DEBUFF_STRIPE_EDGES = GP.DISPEL_OVERLAY_STYLES or {}, GP.DEBUFF_STRIPE_EDGES or {}
local HEALTH_TEXT_MODES = GP.HEALTH_TEXT_MODES or TEXT_MODES
local GF, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection = GP.GF, GP.Conf, GP.Val, GP.QueueGF, GP.Set, GP.Bool, GP.Num, GP.ScopeSection
local CurrentScope = GP.CurrentScope
local SetOptionEnabled, SetOptionsEnabled = GP.SetOptionEnabled, GP.SetOptionsEnabled
local FinalizeScopePage, SetSectionBadgesAndStatus, TrackSectionRefresh = GP.FinalizeScopePage, GP.SetSectionBadgesAndStatus, GP.TrackSectionRefresh
local OnOffBadge, BadgeNumber, OptionText, ControlMeta, RegisterControl = GP.OnOffBadge, GP.BadgeNumber, GP.OptionText, GP.ControlMeta, GP.RegisterControl
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = OptionText or M.OptionText
local GF_DISPEL_OVERLAY_TRIGGERS = VT("BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
    "BY_RAID", "Dispellable by group", "DISPEL_TYPE", "Any dispel type")
local DISPEL_COLOR_REFERENCES = {
    "aura.dispel.magic", "aura.dispel.curse", "aura.dispel.disease",
    "aura.dispel.poison", "aura.dispel.bleed",
}
local function RequestGroupBarsRefresh(ctx, reason)
    if M.RequestRefresh then M.RequestRefresh(ctx, reason or "gf-bars-ui") elseif M.Refresh then M.Refresh(ctx) end
end
local function RawMeta(ctx, path)
    local meta = ControlMeta(ctx, path)
    local kind, field = path:match("^text%.(%a+)%.slot%.([%w_]+)$")
    if field then meta.setting = Schema.TextSlots("group", kind, field) end
    return meta
end
local function StepMeta(ctx, path, step)
    local meta = RawMeta(ctx, path)
    meta.step, meta.roundStep = step, true
    return meta
end
local RAW_COMMANDS = Schema.GroupCommands({}, RawMeta, RawMeta)
local STEP_COMMANDS = Schema.GroupCommands({}, ControlMeta, StepMeta)
local ROW_OPTIONS = { bind = function(ctx, widget, row, kind)
    local options = GROUP_OPTIONS
    if row.get or row.lifecycle or row.bind then options = row.roundStep and STEP_COMMANDS or RAW_COMMANDS end
    options.bind(ctx, widget, row, kind)
end }
local function ScopeNumberCommand(_, ctx, row)
    local key, default, mode = row[2], row[3], row.domain or "visual"
    return {
        get = function() return Num(CurrentScope(), key, default) end,
        set = function(value) Set(CurrentScope(), key, tonumber(value) or default, mode) end,
    }
end
local function NormalizeGFDispelOverlayTrigger(value)
    local gf = GF and GF()
    if gf and type(gf.NormalizeDispelOverlayTrigger) == "function" then return gf.NormalizeDispelOverlayTrigger(value) end
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
    return "BY_ME"
end
local function DispelTriggerCommand(_, ctx, row)
    return {
        get = function() return NormalizeGFDispelOverlayTrigger(Val(CurrentScope(), row[2], "BORDER")) end,
        set = function(value)
            Set(CurrentScope(), row[2], NormalizeGFDispelOverlayTrigger(value), "visual")
            RequestGroupBarsRefresh(ctx, row.reason)
        end,
    }
end
-- The runtime preview setter is resolved once, on first use; the core publishes it before this page loads.
local dispelPreview
local function BuildDispelOverlaySection(ctx, b)
    local c = {}
    local dispel = Schema.Section(b:CollapsibleSection("dispel", "Dispel Overlay", 422, false), "group")
    local dispelW = dispel._msuf2Width or b.width or 720
    local dispelCardW = min(900, max(320, dispelW - 40))
    local dispelCard = Schema.Build(ctx, dispel, {
        { "card", "dispelCard", nil, { nil, nil, 20, -38, dispelCardW, 358 }, scope = "group" },
    }).dispelCard
    Schema.Colors(dispel, DISPEL_COLOR_REFERENCES, {
        title = "Dispel Type Colors",
        note = "Shared by Dispel borders, overlays, symbols, and every related preview.",
        scopeTag = "Shared",
        historySource = "menu:group-dispel-overlay-colors",
        maxTargets = 5,
    })
    Schema.Build(ctx, dispelCard, {
        { "sectionSwitch", "dispelOverlayEnabled", false, { "Dispel Overlay" }, parent = dispel },
        { "dropdown", "dispelOverlayTrigger", "BORDER", { "Overlay detects", GF_DISPEL_OVERLAY_TRIGGERS, 300 }, { 16, -54, min(300, dispelCardW - 32), "LEFT" },
            lifecycle = DispelTriggerCommand, path = "field.dispelOverlayTrigger", reason = "gf-bars-dispel-trigger" },
        { "dropdown", "dispelOverlayStyle", "FULL", { "Overlay style", DISPEL_OVERLAY_STYLES, 300 }, { 16, -106, min(300, dispelCardW - 32), "LEFT" } },
        { "toggle", "dispelOverlayOnHealth", true, { "Show on current health only", 16, -154, dispelCardW - 32 } },
        { "slider", "dispelOverlayAlpha", 0.35, { "Overlay opacity", 0.05, 1, 0.05, 340 }, { 16, -198, min(360, dispelCardW - 72), "CENTER" },
            lifecycle = ScopeNumberCommand, path = "field.dispelOverlayAlpha" },
        { "slider", "dispelOverlayLayer", 0, { "Effect Layer (0-30)", 0, 30, 1, 340 }, { 16, -252, min(360, dispelCardW - 72), "CENTER" },
            lifecycle = ScopeNumberCommand, path = "field.dispelOverlayLayer" },
        -- The live tint is drawn by Blizzard and only appears while a real
        -- dispellable debuff is up, so style, opacity and layer are impossible to
        -- judge while configuring. The preview paints an MSUF-owned stand-in with
        -- the exact same geometry. Ephemeral: never written to the DB.
        { "toggle", "dispelPreview", nil, { "Runtime Preview: live GroupFrames", 16, -300, dispelCardW - 32 },
            path = "field.dispelOverlayPreview", classification = "ephemeral", domain = "preview",
            lifecycle = function(widget)
                return {
                    get = function() return MSUF.PublicGlobals.MSUF_DispelOverlayPreviewMode == true end,
                    set = function(value)
                        dispelPreview = dispelPreview or MSUF.Require("MSUF_SetDispelOverlayPreview", FILE)
                        dispelPreview(value and true or false, CurrentScope())
                    end,
                    afterBind = function()
                        widget:HookScript("OnHide", function(self)
                            if MSUF.PublicGlobals.MSUF_DispelOverlayPreviewMode == true then
                                dispelPreview = dispelPreview or MSUF.Require("MSUF_SetDispelOverlayPreview", FILE)
                                dispelPreview(false)
                                if self.SetChecked then self:SetChecked(false) end
                            end
                        end)
                    end,
                }
            end,
            tip = { "Runtime Preview",
            "Paints a stand-in tint on the live GroupFrames so the overlay can be judged " ..
                "without a real dispellable debuff. Turns itself off when this page closes.",
                { hook = true } },
        },
    }, ROW_OPTIONS, c)
    local dispelControls = { c.dispelOverlayTrigger, c.dispelOverlayStyle, c.dispelOverlayOnHealth, c.dispelOverlayAlpha, c.dispelOverlayLayer,
        c.dispelPreview }
    local function RefreshDispelState()
        if DISPEL_OVERLAY_121_PTR_DISABLED and Bool(CurrentScope(), "dispelOverlayEnabled", false) then
            Set(CurrentScope(), "dispelOverlayEnabled", false, "visual")
        end
        local overlayOn = (not DISPEL_OVERLAY_121_PTR_DISABLED) and Bool(CurrentScope(), "dispelOverlayEnabled", false)
        -- A preview of a disabled overlay would be a lie; drop it with the master.
        if not overlayOn and MSUF.PublicGlobals.MSUF_DispelOverlayPreviewMode == true then
            dispelPreview = dispelPreview or MSUF.Require("MSUF_SetDispelOverlayPreview", FILE)
            dispelPreview(false)
        end
        SetOptionsEnabled(dispelControls, overlayOn)
        SetOptionEnabled(c.dispelOverlayEnabled, not DISPEL_OVERLAY_121_PTR_DISABLED)
        local badges = {
            OnOffBadge(overlayOn, "Active", "Off"),
        }
        if DISPEL_OVERLAY_121_PTR_DISABLED then badges[#badges + 1] = { text = "12.1 PTR", kind = "muted", important = true } end
        badges[#badges + 1] = { text = OptionText(GF_DISPEL_OVERLAY_TRIGGERS, NormalizeGFDispelOverlayTrigger(Val(CurrentScope(), "dispelOverlayTrigger",
            "BORDER")), "Border"), kind = overlayOn and "info" or "muted" }
        badges[#badges + 1] = { text = OptionText(DISPEL_OVERLAY_STYLES, Val(CurrentScope(), "dispelOverlayStyle", "FULL"), "Full Frame"), kind = overlayOn
            and "accent" or "muted" }
        SetSectionBadgesAndStatus(dispel, badges)
    end
    TrackSectionRefresh(ctx, dispel, RefreshDispelState)
end
local GF_DISPEL_SYMBOL_STYLES = UnitSectionShared.DispelSymbolStyles()
local GF_DISPEL_SYMBOL_MODES = VT("TOP", "Highest priority only", "ALL", "One per dispel type")
local GF_DISPEL_SYMBOL_GROWTH = VT("RIGHT", "Right", "LEFT", "Left", "UP", "Up", "DOWN", "Down")
local GF_DISPEL_SYMBOL_ANCHORS = VT("TOPLEFT", "Top Left", "TOP", "Top", "TOPRIGHT", "Top Right",
    "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right",
    "BOTTOMLEFT", "Bottom Left", "BOTTOM", "Bottom", "BOTTOMRIGHT", "Bottom Right")

--- Dispel-type symbol: the indicator that says WHICH debuff type is up. The
--- live symbol is a native AuraButton texture -- Blizzard owns its artwork and
--- visibility -- so Preview is the placement surface even without a real debuff.
local function GFDispelSymbolSectionHeight(ctx)
    local width = min(900, max(320, (((ctx and ctx.width) or 720) - 40)))
    return width >= 760 and 368 or 564
end
local function BindExclusivePowerFill(ctx, control, row)
    row.setting = Schema.Record({ "gf_{scope}." .. row[2], "gf_{scope}." .. row.peer })
    GP.BindExclusiveScopeToggle(ctx, control, row[2], row.peer, row.historyLabel,
        "powerFillMode", function() RequestGroupBarsRefresh(ctx, "gf-power-fill-mode") end)
end

local function BuildGFDispelSymbolSection(ctx, b)
    local c = {}
    local section = Schema.Section(b:CollapsibleSection("dispelSymbol", "Dispel Symbol", GFDispelSymbolSectionHeight(ctx), false), "group")
    local sectionW = section._msuf2Width or b.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    local wide = cardW >= 760
    local card = Schema.Build(ctx, section, {
        { "card", "dispelSymbolCard", nil, { nil, nil, 20, -38, cardW, wide and 304 or 500 }, scope = "group" },
    }).dispelSymbolCard
    local leftX, columnGap = 16, 24
    local controlW = wide and floor((cardW - 32 - columnGap) * 0.5) or min(360, cardW - 32)
    local rightX = wide and (leftX + controlW + columnGap) or leftX
    Schema.Build(ctx, card, {
        { "sectionSwitch", "dispelSymbolEnabled", false, { "Dispel Symbol" }, parent = section },
        { "dropdown", "dispelSymbolStyle", "BLIZZARD", { "Symbol set", GF_DISPEL_SYMBOL_STYLES, 300 }, { leftX, -54, controlW, "LEFT" } },
        { "dropdown", "dispelSymbolMode", "ALL", { "Show", GF_DISPEL_SYMBOL_MODES, 300 }, { leftX, -106, controlW, "LEFT" } },
        { "dropdown", "dispelSymbolTrigger", "BORDER", { "Symbol detects", GF_DISPEL_OVERLAY_TRIGGERS, 300 }, { leftX, -158, controlW, "LEFT" },
            lifecycle = DispelTriggerCommand, path = "field.dispelSymbolTrigger", reason = "gf-bars-dispel-symbol-trigger" },
        { "dropdown", "dispelSymbolAnchor", "TOPRIGHT", { "Symbol anchor", GF_DISPEL_SYMBOL_ANCHORS, 300 }, { rightX, wide and -54 or -306,
            controlW, "LEFT" } },
        { "slider", "dispelSymbolSize", 12, { "Symbol size", 4, 48, 1, 340 }, { leftX, -210, controlW, "CENTER" },
            lifecycle = ScopeNumberCommand, path = "field.dispelSymbolSize" },
        { "dropdown", "dispelSymbolGrowth", "RIGHT", { "Grow", GF_DISPEL_SYMBOL_GROWTH, 300 }, { rightX, wide and -106 or -358, controlW, "LEFT" } },
        { "slider", "dispelSymbolSpacing", 2, { "Symbol spacing", 0, 32, 1, 340 }, { rightX, wide and -158 or -406, controlW, "CENTER" },
            lifecycle = ScopeNumberCommand, path = "field.dispelSymbolSpacing" },
        { "slider", "dispelSymbolAlpha", 1, { "Symbol opacity", 0.05, 1, 0.05, 340 }, { leftX, -258, controlW, "CENTER" },
            lifecycle = ScopeNumberCommand, path = "field.dispelSymbolAlpha" },
        { "slider", "dispelSymbolLayer", 8, { "Effect Layer (0-30)", 0, 30, 1, 340 }, { rightX, wide and -210 or -454, controlW, "CENTER" },
            lifecycle = ScopeNumberCommand, path = "field.dispelSymbolLayer" },
    }, ROW_OPTIONS, c)
    -- No preview toggle here. The symbols are previewed in the group preview
    -- above as their own "Dispel" layer -- like every other group element -- and
    -- that layer's handle is also the drag surface for placement.
    local controls = { c.dispelSymbolStyle, c.dispelSymbolMode, c.dispelSymbolTrigger, c.dispelSymbolAnchor, c.dispelSymbolSize,
        c.dispelSymbolAlpha, c.dispelSymbolLayer }
    local allModeControls = { c.dispelSymbolGrowth, c.dispelSymbolSpacing }
    local function RefreshDispelSymbolState()
        local on = Bool(CurrentScope(), "dispelSymbolEnabled", false)
        SetOptionsEnabled(controls, on)
        SetOptionsEnabled(allModeControls, on and Val(CurrentScope(), "dispelSymbolMode", "ALL") == "ALL")
        SetOptionEnabled(c.dispelSymbolEnabled, true)
        local badges = {
            OnOffBadge(on, "Active", "Off"),
            { text = OptionText(GF_DISPEL_SYMBOL_STYLES, Val(CurrentScope(), "dispelSymbolStyle", "BLIZZARD"), "Blizzard symbol"), kind = on
                and "accent" or "muted" },
            { text = OptionText(GF_DISPEL_SYMBOL_MODES, Val(CurrentScope(), "dispelSymbolMode", "ALL"), "One per dispel type"), kind = on
                and "info" or "muted" },
        }
        SetSectionBadgesAndStatus(section, badges)
    end
    TrackSectionRefresh(ctx, section, RefreshDispelSymbolState)
end

local function DefaultPowerHeight(kind)
    kind = kind or CurrentScope()
    return (kind == "raid" or kind == "mythicraid") and 4 or 6
end
local function IsPowerBarEnabled(kind)
    local conf = Conf(kind or CurrentScope())
    if not conf then return false end
    if conf.powerBarEnabled == false then return false end
    local raw = tonumber(conf.powerHeight)
    if raw ~= nil and raw <= 0 then return false end
    return true
end
local function CurrentPowerHeight(kind)
    kind = kind or CurrentScope()
    local raw = tonumber(Conf(kind).powerHeight)
    if raw and raw > 0 then return raw end
    return DefaultPowerHeight(kind)
end
local function PreparePowerSwitch(ctx, power)
    local entry = power and power._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local powerEnabled = Schema.Build(ctx, power, {
        { "sectionSwitch", "powerEnabled", nil, { "Show Power Bar" }, path = "field.powerBarEnabled", domain = "geometry",
            get = function() return IsPowerBarEnabled(CurrentScope()) end,
            set = function(v)
                local scope = CurrentScope()
                Set(scope, "powerBarEnabled", v and true or false, "geometry")
                if v and (tonumber(Conf(scope).powerHeight) or 0) <= 0 then Set(scope, "powerHeight", DefaultPowerHeight(scope), "geometry") end
                RequestGroupBarsRefresh(ctx, "gf-bars-power-enabled")
            end },
    }, ROW_OPTIONS).powerEnabled
    powerEnabled:SetChecked(IsPowerBarEnabled(CurrentScope()))
    return powerEnabled
end
local function PrepareRangeSwitch(ctx, range)
    local entry = range and range._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local toggle = Schema.Build(ctx, range, {
        { "sectionSwitch", "rangeFadeEnabled", false, { "Range Fade" } },
    }, ROW_OPTIONS).rangeFadeEnabled
    toggle:SetChecked(Bool(CurrentScope(), "rangeFadeEnabled", false))
    return toggle
end
-- Resource Bar section. BuildGFResourceBarSection runs three stages that share one state table (`s`):
-- cards with Visibility & Size, Border & fill with Roles and Detached placement, then the refresh.
-- The stages create their widgets in the order the single builder did, so the layout is unchanged.
local function FocusPreviewRole(ctx, control, role)
    if not (control and control.HookScript) then return end
    control:HookScript("OnClick", function()
        local scope = CurrentScope()
        M.gfPreviewRoles = M.gfPreviewRoles or {}
        M.gfPreviewRoles[scope] = role
        RequestGroupBarsRefresh(ctx, "gf-bars-preview-role")
    end)
end
local function PowerCardsAndSize(ctx, b, c)
    -- Self-sizing section: the cards reserve their own rows through W.NextRow and
    -- b:FinishSection derives the height from the cursor. A hand-declared height
    -- here silently under-sizes the body and lets the cards bleed over the
    -- sections below once a card is added or grows.
    local power = b:CollapsibleSection("power", "Resource Bar", nil, false)
    if not power._msuf2CollapsibleEntry.header._msuf2ControlSchema then Schema.Section(power, "group") end
    local leftX, leftW, rightX, rightW, innerW = Schema.Columns(power, b.width or 720, 20, 16, 0.54)
    local sliderW = max(180, min(360, leftW - 64))
    -- Card set mirrors the unit-frame Resource Bar section (Visibility & Size,
    -- Border & fill, Detached placement); Roles is the group-only addition.
    -- Bar art and colour stay off this page for the same reason they are off the
    -- unit page: they are configured once globally.
    local powerCardH = 250
    local roleCardH = 178
    local detachedCardH = 244
    local _, powerCardY = W.NextRow(power, powerCardH + 12)
    local _, roleCardY = W.NextRow(power, roleCardH + 12)
    local _, detachedCardY = W.NextRow(power, detachedCardH)
    Schema.Build(ctx, power, {
        { "card", "powerMain", nil, { "Visibility & Size", nil, leftX, powerCardY, leftW, powerCardH, "group" }, scope = "group" },
        { "card", "powerBorderCard", nil, { "Border & fill", "Outline and fill behavior.", rightX, powerCardY, rightW, powerCardH,
            "group" }, scope = "group" },
        { "card", "powerRoles", nil, { "Roles", nil, leftX, roleCardY, leftW, roleCardH, "group" }, scope = "group" },
        { "card", "powerDetached", nil, { "Detached placement", "Used only when the power bar is detached from the frame.",
            leftX, detachedCardY, innerW, detachedCardH, "group" }, scope = "group" },
    }, nil, c)
    local main, border, detachedGap = c.powerMain, c.powerBorderCard, 16
    local detachedColW = floor((innerW - 32 - detachedGap) / 2)
    local s = {
        power = power, main = main, border = border, roles = c.powerRoles, detached = c.powerDetached,
        leftW = leftW, rightW = rightW, sliderW = sliderW, detachedColW = detachedColW,
        detachedRightX = 16 + detachedColW + detachedGap, detachedSliderW = max(160, min(340, detachedColW - 40)),
    }
    -- Party and raid rosters mix every resource type at once, so guessing a
    -- single token for the whole group only ever named the wrong resource.
    -- The card lists them instead; each entry is that resource's shared
    -- color, so the mapping is a list and states its own target bound.
    Schema.Colors(main, {
        "power.token.mana", "power.token.rage", "power.token.energy",
        "power.token.focus", "power.token.runic_power", "power.token.insanity",
        "power.token.fury", "power.token.pain", "power.token.essence",
        "power.token.lunar_power", "power.token.maelstrom",
        "group.background",
    }, {
        title = "Group Resource Bar Colors",
        note = "One color per resource type, shared with every frame.",
        historySource = "menu:group-resource-bar-colors",
        offsetX = -76,
        maxTargets = 12,
    })
    Schema.Colors(border, { "bar.power_loss" }, {
        title = "Power Loss Color",
        note = "Changes only the disappearing loss glow and is shared by every frame.",
        historySource = "menu:group-power-loss-color",
    })
    s.enabled = PreparePowerSwitch(ctx, power)
    Schema.Build(ctx, main, {
        { "slider", "powerHeight", DefaultPowerHeight(), { "Power height", 1, 30, 1, sliderW }, path = "field.powerHeight",
            domain = "geometry", roundStep = true,
            get = function() return CurrentPowerHeight(CurrentScope()) end,
            set = function(v)
                v = floor(max(1, min(30, tonumber(v) or CurrentPowerHeight(CurrentScope()))) + 0.5)
                Set(CurrentScope(), "powerHeight", v, "geometry")
            end },
        -- Embed/detach change layout, so they take the geometry dirty class; the
        -- header can only re-lay out its rows outside combat.
        { "toggle", "embedPowerBarIntoHealth", true, { "Embed into health", 16, -138, leftW - 32 }, domain = "geometry" },
        { "toggle", "detachPower", nil, { "Detach from frame", 16, -166, leftW - 32 }, path = "field.powerBarDetached", domain = "geometry",
            get = function() return Bool(CurrentScope(), "powerBarDetached", false) end,
            set = function(v)
                local scope = CurrentScope()
                local conf = Conf(scope)
                if v and not ((tonumber(conf.detachedPowerBarWidth) or 0) > 0) then
                    -- Seed the geometry the detached card edits, mirroring the unit page.
                    conf.detachedPowerBarWidth = tonumber(conf.width) or 80
                end
                Set(scope, "powerBarDetached", v and true or false, "geometry")
                RequestGroupBarsRefresh(ctx, "gf-bars-power-detached")
            end },
        { "text", "powerHint", nil, { "Power text modes, delimiter and font size are in Text.", 16, -194, leftW - 32,
            { 0.60, 0.75, 1.00, 1 } }, scope = "group" },
    }, ROW_OPTIONS, c)
    if c.powerHint.SetWordWrap then c.powerHint:SetWordWrap(true) end
    return s
end
local function PowerBorderRolesDetached(ctx, s, c)
    local leftW, rightW, detachedColW, detachedSliderW = s.leftW, s.rightW, s.detachedColW, s.detachedSliderW
    Schema.Build(ctx, s.border, {
        { "toggle", "powerBorder", nil, { "Power bar border", 16, -62, rightW - 32 }, path = "field.powerBarBorderEnabled", domain = "color",
            get = function() return Bool(CurrentScope(), "powerBarBorderEnabled", false) end,
            set = function(v)
                Set(CurrentScope(), "powerBarBorderEnabled", v and true or false, "color")
                RequestGroupBarsRefresh(ctx, "gf-bars-power-border")
            end },
        { "slider", "powerBarBorderThickness", 1, { "Border thickness", 0, 6, 1, rightW - 72 }, { 16, -108, rightW - 72, "CENTER" },
            domain = "color" },
        { "toggle", "powerSmoothFill", false, { "Smooth fill", 16, -158, rightW - 32 }, bind = BindExclusivePowerFill,
            peer = "powerChunkedFill", historyLabel = "Smooth group power fill" },
        { "toggle", "powerChunkedFill", false, { "Chunked power loss", 16, -188, rightW - 32 }, bind = BindExclusivePowerFill,
            peer = "powerSmoothFill", historyLabel = "Chunked group power loss" },
    }, ROW_OPTIONS, c)
    s.roleLabel = s.roles and s.roles.title
    Schema.Build(ctx, s.roles, {
        { "toggle", "powerShowTank", true, { "Tank", 16, -66, leftW - 32 } },
        { "toggle", "powerShowHealer", true, { "Healer", 16, -100, leftW - 32 } },
        { "toggle", "powerShowDamager", false, { "DPS", 16, -134, leftW - 32 } },
    }, ROW_OPTIONS, c)
    FocusPreviewRole(ctx, c.powerShowTank, "TANK")
    FocusPreviewRole(ctx, c.powerShowHealer, "HEALER")
    FocusPreviewRole(ctx, c.powerShowDamager, "DAMAGER")
    W.MoveWidget(c.powerHeight, s.main, 16, -76, s.sliderW, "LEFT")
    -- Detached placement: the same fields a non-Player unit frame gets. Class
    -- Resource width sync, anchor and the ROUND/CRYSTAL/ORB shapes are Player-only
    -- on the unit page, so group members do not get them either.
    Schema.Build(ctx, s.detached, {
        { "toggle", "detachedPowerBarTextOnBar", false, { "Text on detached bar", 16, -62, detachedColW }, domain = "geometry" },
        { "slider", "detachedPowerBarWidth", 80, { "Detached width", 20, 800, 1, detachedSliderW }, { 16, -116, detachedSliderW, "CENTER" },
            domain = "geometry" },
        { "slider", "detachedPowerBarHeight", 6, { "Detached height", 2, 80, 1, detachedSliderW }, { s.detachedRightX, -116, detachedSliderW,
            "CENTER" }, domain = "geometry" },
        { "slider", "detachedPowerBarFrameLevelOffset", 6, { "Detached layer", 0, 30, 1, detachedSliderW }, { 16, -182, detachedSliderW,
            "CENTER" }, domain = "geometry" },
    }, ROW_OPTIONS, c)
end
local function BuildGFResourceBarSection(ctx, b)
    local c = {}
    local s = PowerCardsAndSize(ctx, b, c)
    PowerBorderRolesDetached(ctx, s, c)
    ctx:AddResizeCallback(function()
        local leftX, leftW, rightX, rightW, innerW = Schema.Columns(s.power, b.width or 720, 20, 16, 0.54)
        for _, card in ipairs({ s.main, s.border, s.roles, s.detached }) do
            local cardW = card == s.detached and innerW or (card == s.border and rightW or leftW)
            M.ResizePageSurface(card, cardW)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", s.power, "TOPLEFT", card == s.border and rightX or leftX, card._msuf2ContextColorTop)
            card._msuf2ContextColorLeft = card == s.border and rightX or leftX
            card._msuf2ContextColorWidth = cardW
        end
        W.MoveWidget(c.powerHeight, s.main, 16, -76, max(180, min(360, leftW - 64)), "LEFT")
        W.MoveWidget(c.embedPowerBarIntoHealth, s.main, 16, -138, leftW - 32)
        W.MoveWidget(c.detachPower, s.main, 16, -166, leftW - 32)
        W.MoveWidget(c.powerBorder, s.border, 16, -62, rightW - 32)
        W.MoveWidget(c.powerBarBorderThickness, s.border, 16, -108, rightW - 72, "CENTER")
        W.MoveWidget(c.powerSmoothFill, s.border, 16, -158, rightW - 32)
        W.MoveWidget(c.powerChunkedFill, s.border, 16, -188, rightW - 32)
        W.MoveWidget(c.powerShowTank, s.roles, 16, -66, leftW - 32)
        W.MoveWidget(c.powerShowHealer, s.roles, 16, -100, leftW - 32)
        W.MoveWidget(c.powerShowDamager, s.roles, 16, -134, leftW - 32)
        local column = floor((innerW - 48) / 2)
        local slider = max(160, min(340, column - 40))
        W.MoveWidget(c.detachedPowerBarTextOnBar, s.detached, 16, -62, column)
        W.MoveWidget(c.detachedPowerBarWidth, s.detached, 16, -116, slider, "CENTER")
        W.MoveWidget(c.detachedPowerBarHeight, s.detached, 32 + column, -116, slider, "CENTER")
        W.MoveWidget(c.detachedPowerBarFrameLevelOffset, s.detached, 16, -182, slider, "CENTER")
    end)
    local power, powerEnabled, roleLabel = s.power, s.enabled, s.roleLabel
    local powerControls = {
        c.powerHeight, c.powerSmoothFill, c.powerChunkedFill, c.powerShowTank, c.powerShowHealer, c.powerShowDamager,
        c.embedPowerBarIntoHealth, c.detachPower, c.powerBorder,
    }
    local detachedControls = { c.detachedPowerBarTextOnBar, c.detachedPowerBarWidth, c.detachedPowerBarHeight, c.detachedPowerBarFrameLevelOffset }
    local function RefreshPowerState()
        local enabled = IsPowerBarEnabled(CurrentScope())
        local detached = enabled and Bool(CurrentScope(), "powerBarDetached", false)
        SetOptionEnabled(powerEnabled, true)
        SetOptionsEnabled(powerControls, enabled)
        SetOptionEnabled(c.powerHeight, enabled and not detached)
        SetOptionEnabled(c.embedPowerBarIntoHealth, enabled and not detached)
        -- Same gating the unit page applies: detached geometry only while the bar
        -- is detached, thickness only while the border is on.
        SetOptionsEnabled(detachedControls, detached)
        SetOptionEnabled(c.powerBarBorderThickness, enabled and Bool(CurrentScope(), "powerBarBorderEnabled", false))
        if roleLabel.SetTextColor then
            local color = enabled and T.colors.accent or T.colors.dim
            roleLabel:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        local roles = {}
        if Bool(CurrentScope(), "powerShowTank", true) then roles[#roles + 1] = "Tank" end
        if Bool(CurrentScope(), "powerShowHealer", true) then roles[#roles + 1] = "Healer" end
        if Bool(CurrentScope(), "powerShowDamager", false) then roles[#roles + 1] = "DPS" end
        SetSectionBadgesAndStatus(power, {
            OnOffBadge(enabled, "Shown", "Hidden"),
            { text = M.Format("%s px", BadgeNumber(CurrentPowerHeight(CurrentScope()))), kind = enabled and "info" or "muted" },
            { text = #roles > 0 and table.concat(roles, "/") or "No roles", kind = enabled and "accent" or "muted" },
            { text = detached and "Detached" or "Attached", kind = enabled and "info" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, power, RefreshPowerState)
    if b.FinishSection then b:FinishSection(power, 24) end
end

-- Group Text section. BuildGFTextSection runs a sequence of stages that share one state table
-- (`s`): layout, tab state, tab shell, Name tab, HP and Power tabs, Advanced tab, refresh. The
-- stages create their widgets in the order the single builder did, so the layout is unchanged.
-- Preview example strings and focus helpers that need no per-build state are module-level.
-- Every absorb mode is its base mode with an ABSORB suffix (CURMAXABSORB -> CURMAX).
local GF_ABSORB_MODE_BASE = {}
for _, base in ipairs({ "CURRENT", "FULLVALUE", "MAX", "DEFICIT", "CURMAX", "PERCENT", "CURPERCENT", "CURMAXPERCENT", "MAXPERCENT",
    "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX", "MAXCUR", "PERCENTMAXCUR" }) do
    GF_ABSORB_MODE_BASE[base .. "ABSORB"] = base
end
local GF_ABSORB_ICON_MARKUP = "|TInterface\\Icons\\INV_Shield_06:0|t"
local function TextModeExampleStr(mode, delim, isPower, decimalHP, hidePercentSymbol, shortNumbers, absorbIcon)
    local absorbBase = GF_ABSORB_MODE_BASE[mode]
    local cur     = isPower and "100"  or (shortNumbers and "12.5k" or "12,450")
    local max_    = isPower and "100"  or (shortNumbers and "15.0k" or "15,000")
    local absorb  = shortNumbers and "3.8k" or "3,750"
    local absorbText = (absorbIcon and (GF_ABSORB_ICON_MARKUP .. " ") or "") .. absorb
    local pct     = isPower and "100" or (decimalHP and "83.0" or "83")
    if hidePercentSymbol ~= true then pct = pct .. "%" end
    local deficit = isPower and "0"    or (shortNumbers and "-2.6k" or "-2,550")
    if mode == "ABSORB" then return absorbText end
    mode = absorbBase or mode
    local value
    if mode == "PERCENT" then value = pct
    elseif mode == "CURRENT" or mode == "FULLVALUE" then value = cur
    elseif mode == "MAX" then value = max_
    elseif mode == "DEFICIT" then value = deficit
    elseif mode == "CURMAX" then value = cur .. delim .. max_
    elseif mode == "MAXCUR" then value = max_ .. delim .. cur
    elseif mode == "CURPERCENT" then value = cur .. delim .. pct
    elseif mode == "CURMAXPERCENT" then value = cur .. delim .. max_ .. delim .. pct
    elseif mode == "MAXPERCENT" then value = max_ .. delim .. pct
    elseif mode == "PERCENTCUR" then value = pct .. delim .. cur
    elseif mode == "PERCENTMAX" then value = pct .. delim .. max_
    elseif mode == "PERCENTCURMAX" then value = pct .. delim .. cur .. delim .. max_
    elseif mode == "PERCENTMAXCUR" then value = pct .. delim .. max_ .. delim .. cur end
    if not value then return nil end
    return absorbBase and (value .. " + " .. absorbText) or value
end
local function TextModeHasPercent(mode)
    return tostring(mode or ""):find("PERCENT", 1, true) ~= nil
end
-- The group text DB owns the reversed-order mapping (GroupFrames/
-- MSUF_GroupFrames_DB_Text.lua), loaded with the core on every client.
local function ReverseHpPreviewMode(mode)
    return MSUF.GF.ReverseHealthTextMode(mode)
end
local function BuildTextPreviewStr(leftMode, centerMode, rightMode, delim, reverse, isPower, decimalHP, shortNumbers, hideLeft, hideCenter, hideRight,
    absorbIconLeft, absorbIconCenter, absorbIconRight)
    if reverse and not isPower then
        leftMode, centerMode, rightMode = ReverseHpPreviewMode(rightMode), ReverseHpPreviewMode(centerMode), ReverseHpPreviewMode(leftMode)
        hideLeft, hideRight = hideRight, hideLeft
        absorbIconLeft, absorbIconRight = absorbIconRight, absorbIconLeft
    end
    local slots = { leftMode, centerMode, rightMode }
    local hideSlots = { hideLeft, hideCenter, hideRight }
    local iconSlots = { absorbIconLeft, absorbIconCenter, absorbIconRight }
    local parts = {}
    for i, mode in ipairs(slots) do
        local ex = TextModeExampleStr(mode, delim, isPower, decimalHP, hideSlots[i], shortNumbers, iconSlots[i])
        if ex then parts[#parts + 1] = ex end
    end
    return #parts > 0 and table.concat(parts, "  ") or "(none)"
end
local function SlotHidePercentSymbol(scope, key)
    local conf = Conf(scope)
    if conf and conf[key] ~= nil then return conf[key] == true end
    local db = M.EnsureDB and M.EnsureDB()
    local g = db and db.general
    return g and g.hidePercentSymbol == true
end
local function CurrentTextTab()
    local scope = CurrentScope()
    local key = M.gfTextTabSelection[scope] or "name"
    if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
    return key
end
local function CurrentScopeKey()
    local scope = CurrentScope()
    if scope == "raid" then return "gf_raid" end
    if scope == "mythicraid" then return "gf_mythicraid" end
    return "gf_party"
end
-- Hover and click handlers run this, so the Edit Mode focus functions are resolved once, at load.
local focusSelection = MSUF.Require("MSUF_EM2_SetFocusSelection", FILE)
local focusHover = MSUF.Require("MSUF_EM2_SetFocusHover", FILE)
local focusClear = MSUF.Require("MSUF_EM2_ClearFocusHover", FILE)
local function FocusGFPreviewText(kind, slot, active)
    if type(M.FocusGFPreviewTextSlot) == "function" then M.FocusGFPreviewTextSlot(kind, slot, active == true) end
    if kind then
        if active == true then
            focusSelection(CurrentScopeKey(), kind, slot, { source = "menu2", clearHover = true })
        else
            focusHover(CurrentScopeKey(), kind, slot, { source = "menu2" })
        end
    else
        focusClear()
    end
end
local function ResolveFocusSlot(slot)
    if type(slot) == "function" then return slot() end
    return slot
end
-- Slot, setting key. No literal defaults: Val answers the scope's own
-- default (GF.Val), which differs between Party and Raid.
local GF_TEXT_SUMMARY_SLOTS = {}
for kind, prefix in pairs({ hp = "text", power = "powerText" }) do
    GF_TEXT_SUMMARY_SLOTS[kind] = { { "right", prefix .. "Right" }, { "center", prefix .. "Center" }, { "left", prefix .. "Left" } }
end
local function TextSlotSummary(kind)
    local scope = CurrentScope()
    return UnitSectionShared.TextSlotSummary(kind, GF_TEXT_SUMMARY_SLOTS, function(slot)
        return Val(scope, slot[2])
    end, kind == "hp" and HEALTH_TEXT_MODES or TEXT_MODES, OptionText)
end
local function PreviewText(parent, textValue, x, y, width)
    local label, value = UnitSectionShared.PreviewText(parent, textValue, x, y, width, T.colors.dim)
    Schema.Custom(value, { id = parent._msuf2ControlSchema.id .. ".preview", kind = "preview", scope = "group",
        applyDomain = "preview", owner = value, label = label })
    return value
end
local function IsPowerTextEnabled()
    local gf = GF()
    if gf and type(gf.IsPowerTextEnabled) == "function" then return gf.IsPowerTextEnabled(CurrentScope(), Conf(CurrentScope())) and true or false end
    return Bool(CurrentScope(), "showPowerText", false) or Bool(CurrentScope(), "showPower", false)
end
local function SetPowerTextEnabled(enabled)
    local gf = GF()
    if gf and type(gf.SetPowerTextEnabled) == "function" then
        gf.SetPowerTextEnabled(CurrentScope(), enabled and true or false)
        QueueGF(CurrentScope(), "visual")
    else
        Set(CurrentScope(), "showPowerText", enabled and true or false, "visual")
        Set(CurrentScope(), "showPower", enabled and true or false, "visual")
    end
end
local SLOT_VALUES = VT("left", "Left slot", "center", "Center slot", "right", "Right slot")
local ABSORB_STYLE_VALUES = VT("off", "Off", "value", "+ Value", "icon", "|TInterface\\Icons\\INV_Shield_06:14|t + Value")
local function FocusActiveGFPreviewText(s)
    local tab = CurrentTextTab()
    local MoveTogether, CurrentSlot = s.slots.MoveTogether, s.slots.CurrentSlot
    if tab == "name" then
        FocusGFPreviewText("name", nil, true)
    elseif tab == "hp" or tab == "power" then
        local selectedSlot
        if not MoveTogether(tab) then selectedSlot = CurrentSlot(tab) end
        FocusGFPreviewText(tab, selectedSlot, true)
    else
        FocusGFPreviewText(nil, nil, false)
    end
end
local function RestoreGFPreviewTextFocus(s)
    if s.refresh then
        s.refresh()
    else
        FocusActiveGFPreviewText(s)
    end
end
local function ActivateGFPreviewText(s, kind, slot)
    local resolvedSlot = ResolveFocusSlot(slot)
    if (kind == "hp" or kind == "power") and resolvedSlot then s.slots.SetCurrentSlot(kind, resolvedSlot) end
    FocusGFPreviewText(kind, resolvedSlot, true)
end
local function HookGFPreviewTextFocus(s, widget, kind, slot)
    if not (widget and widget.HookScript) then return end
    widget:HookScript("OnEnter", function()
        FocusGFPreviewText(kind, ResolveFocusSlot(slot), false)
    end)
    widget:HookScript("OnMouseDown", function()
        ActivateGFPreviewText(s, kind, slot)
    end)
    widget:HookScript("OnLeave", function() RestoreGFPreviewTextFocus(s) end)
end
local function UpdateTextHeaderBadges(s, tab, nameOn, hpOn, powerOn)
    local scope = CurrentScope()
    local badges
    if tab == "hp" then
        badges = {
            { text = hpOn and "Shown" or "Hidden", kind = hpOn and "ok" or "muted" },
            { text = TextSlotSummary("hp"), kind = hpOn and "info" or "muted" },
            { text = "Preview position", kind = hpOn and "accent" or "muted" },
        }
    elseif tab == "power" then
        badges = {
            { text = powerOn and "Shown" or "Hidden", kind = powerOn and "ok" or "muted" },
            { text = TextSlotSummary("power"), kind = powerOn and "info" or "muted" },
            { text = "Preview position", kind = powerOn and "accent" or "muted" },
        }
    elseif tab == "advanced" then
        badges = {
            { text = M.Format("Name %s", BadgeNumber(Val(scope, "nameTextLayer", 5))), kind = nameOn and "info" or "muted" },
            { text = M.Format("HP %s", BadgeNumber(Val(scope, "textLayer", 5))), kind = hpOn and "info" or "muted" },
            { text = M.Format("Power %s", BadgeNumber(Val(scope, "powerTextLayer", 2))), kind = powerOn and "info" or "muted" },
        }
    else
        badges = {
            { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
            { text = UnitSectionShared.TextBadgeValue(OptionText(ANCHORS, Val(scope, "nameAnchor", "LEFT"))), kind = nameOn and "info" or "muted" },
            { text = "Preview position", kind = nameOn and "accent" or "muted" },
        }
    end
    SetSectionBadgesAndStatus(s.text, badges)
end
local function GFTextLayout(b)
    local s = {}
    -- HP tab: 64px tab inset + 430px content card + bottom breathing room.
    local text = b:CollapsibleSection("text", "Text", 522, false)
    if not text._msuf2CollapsibleEntry.header._msuf2ControlSchema then Schema.Section(text, "group") end
    text._msuf2CollapsibleBadgesOnlyWhenOpen = true
    local textW = text._msuf2Width or b.width or 720
    local textLeftX = 24
    local textCardW = min(520, max(360, textW - 48))
    local textRightX = textLeftX + textCardW + 28
    local textRightW = min(360, max(260, textW - textRightX - 28))
    local textSliderW = min(310, max(230, textCardW))
    local hpSliderW = min(310, max(230, textRightW))
    local textDropW = min(310, max(220, textCardW))
    local textHalfDropW = floor((textCardW - 44) / 2)
    s.text, s.textW, s.textLeftX, s.textCardW = text, textW, textLeftX, textCardW
    s.textRightX, s.textRightW, s.textSliderW = textRightX, textRightW, textSliderW
    s.hpSliderW, s.textDropW, s.textHalfDropW = hpSliderW, textDropW, textHalfDropW
    return s
end
local function GFTextState(s)
    s.text._msuf2CursorY = -12
    M.gfTextTabSelection = M.gfTextTabSelection or {}
    s.slots = UnitSectionShared.MakeTextSlotState(M, CurrentScope, "gfTextSlotSelection", "gfTextMoveTogether")
end
local function GFTextTabs(ctx, s)
    local text, textW = s.text, s.textW
    local SetCurrentSlot, CurrentSlot = s.slots.SetCurrentSlot, s.slots.CurrentSlot
    local tabValues = VT("name", "Name", "hp", "HP Text", "power", "Power Text", "advanced", "Advanced")
    local tabFrames = {}
    local nameTab, hpTab, powerTab, advancedTab =
        M.UnitSectionsShared.MakeTabFrames(text, -64, textW, tabFrames, "name", "hp", "power", "advanced")
    local textTabs, RefreshTextTabs, ReadTextTab, SetGuidedTextTab = W.SegmentTabs(ctx, text, {
        label = "", values = tabValues, width = min(520, textW - 48),
        frames = tabFrames, defaultTab = "name",
        get = CurrentTextTab,
        set = function(v) M.gfTextTabSelection[CurrentScope()] = v or "name" end,
        afterSet = function()
            FocusActiveGFPreviewText(s)
            if s.refresh then s.refresh() end
        end,
        x = 20, y = -12,
    })
    if textTabs._msuf2Title then textTabs._msuf2Title:Hide() end
    RegisterControl(textTabs, ctx, "text.workspace_tab", "Text area", "segment", "ephemeral")
    Schema.Owned(textTabs, "group", "menuState")
    text._msuf2GuidedSelectTab = function(tab)
        if tab ~= "name" and tab ~= "hp" and tab ~= "power" and tab ~= "advanced" then return false end
        if type(ReadTextTab) == "function" and ReadTextTab() == tab then return true end
        if type(SetGuidedTextTab) == "function" then
            SetGuidedTextTab(tab)
        else
            M.gfTextTabSelection[CurrentScope()] = tab
            if type(RefreshTextTabs) == "function" then RefreshTextTabs() end
        end
        return type(ReadTextTab) ~= "function" or ReadTextTab() == tab
    end
    text._msuf2GuidedSelectSlot = function(kind, slot)
        if (kind ~= "hp" and kind ~= "power") or (slot ~= "left" and slot ~= "center" and slot ~= "right") then return false end
        SetCurrentSlot(kind, slot)
        if s.refresh then s.refresh() end
        return CurrentSlot(kind) == slot
    end
    s.nameTab, s.hpTab, s.powerTab, s.advancedTab, s.RefreshTextTabs = nameTab, hpTab, powerTab, advancedTab, RefreshTextTabs
end
local function GFTextNameTab(ctx, s)
    local c = {}
    local nameTab, textLeftX, textCardW = s.nameTab, s.textLeftX, s.textCardW
    local textRightX, textRightW, textDropW, hpSliderW = s.textRightX, s.textRightW, s.textDropW, s.hpSliderW
    local nameContent = Schema.Build(ctx, nameTab, {
        { "card", "nameContent", nil, { nil, nil, textLeftX, -4, textCardW, 158 }, scope = "group" },
    }).nameContent
    Schema.Colors(nameContent, nil, {
        title = "Name Text settings",
        historyLabel = "Group name color",
        historySource = "menu:group-text-name-color",
        offsetY = -24,
        textSettings = {
            scope = function() return CurrentScope() end,
            group = true,
            kind = "name",
        },
    })
    PreviewText(nameContent, "Mapko", 16, -54, textCardW - 32)
    Schema.Build(ctx, nameContent, {
        { "switch", "showName", true, { "Show Name", 16, -24, 0, "HIDDEN" }, domain = "font" },
        { "toggle", "hideNameOnDeadOffline", false, { "Hide name on dead/offline", 16, -104, textCardW - 32 } },
    }, ROW_OPTIONS, c)
    local namePosition = Schema.Build(ctx, nameTab, {
        { "card", "namePosition", nil, { "Position", "Move the name directly in Preview.", textLeftX, -178, textCardW, 134 }, scope = "group" },
    }).namePosition
    Schema.Build(ctx, namePosition, {
        { "dropdown", "nameAnchor", "LEFT", { "Anchor", ANCHORS, textDropW }, { 16, -48, textCardW - 32, "LEFT" }, domain = "font" },
    }, ROW_OPTIONS, c)
    local nameAppearance = Schema.Build(ctx, nameTab, {
        { "card", "nameAppearance", nil, { "Appearance", nil, textRightX, -4, textRightW, 150 }, scope = "group" },
    }).nameAppearance
    Schema.Build(ctx, nameAppearance, {
        { "slider", "nameFontSize", 12, { "Size", 6, 48, 1, hpSliderW }, { 16, -58, textRightW - 58, "CENTER" }, domain = "font" },
    }, ROW_OPTIONS, c)
    s.showName, s.hideNameOnStatus, s.nameAnchor, s.nameSize = c.showName, c.hideNameOnDeadOffline, c.nameAnchor, c.nameFontSize
end
-- One value tab (HP or Power) is built in two stages: the content card with the slot rows, then the
-- formatting rows and the Position card. They create their widgets in the order the single builder did.
local function ValueTabSlots(ctx, s, kind, tab, cfg)
    local textLeftX, textCardW = s.textLeftX, s.textCardW
    local CurrentSlot, SetCurrentSlot = s.slots.CurrentSlot, s.slots.SetCurrentSlot
    local controls = {}
    local hasAbsorb = cfg.absorbIconKey ~= nil
    local contentHeight = hasAbsorb and 430 or 370
    local showKey, path = cfg.showKey or "show", "text." .. kind .. "."
    local content = Schema.Build(ctx, tab, {
        { "card", path .. "content", nil, { nil, nil, textLeftX, -4, textCardW, contentHeight }, scope = "group" },
    })[path .. "content"]
    Schema.Colors(content, nil, {
        title = kind == "hp" and "HP Text settings" or "Power Text settings",
        historyLabel = kind == "hp" and "Group HP text color" or "Group power text color",
        historySource = "menu:group-text-" .. tostring(kind) .. "-color",
        offsetY = -24,
        textSettings = { scope = function() return CurrentScope() end, group = true, kind = kind },
    })
    controls.preview = PreviewText(content, "", 16, -54, textCardW - 32)
    controls.show = Schema.Build(ctx, content, {
        { "switch", showKey, cfg.showDefault, { cfg.showLabel, 16, -24, 0, "HIDDEN" }, domain = cfg.showGet and "visual" or "font",
            get = cfg.showGet, set = cfg.showSet, path = cfg.showGet and path .. "show" or nil },
    }, ROW_OPTIONS)[showKey]
    local function SelectedSlotSpec()
        return cfg.slots[CurrentSlot(kind)] or cfg.slots.center
    end
    local function CurrentMode()
        local spec = SelectedSlotSpec()
        return Val(CurrentScope(), spec.key, spec.default)
    end
    local function TextEnabled()
        return cfg.showGet and cfg.showGet() or Bool(CurrentScope(), cfg.showKey, cfg.showDefault)
    end
    local function AfterModeChanged(mode)
        FocusGFPreviewText(kind, CurrentSlot(kind), true)
        if controls.RefreshPercentToggles then controls.RefreshPercentToggles(TextEnabled()) end
        if controls.RefreshAbsorbControl then controls.RefreshAbsorbControl(TextEnabled()) end
        if controls.RefreshShortNumbersToggle then controls.RefreshShortNumbersToggle(TextEnabled()) end
        if mode == "FULLVALUE" and controls.shortNumbers and T.PlayNeonFlash then
            T.PlayNeonFlash(controls.shortNumbers, "info", { alpha = 0.26, duration = 0.85 })
        end
        RequestGroupBarsRefresh(ctx, "gf-bars-text-mode")
    end
    local rows = {
        { "segment", "slot", nil, { "Text slots", SLOT_VALUES, textCardW - 32 }, path = path .. "slot_selector",
            classification = "ephemeral", domain = "menuState",
            beforeBind = function(widget) W.MoveWidget(widget, content, 16, -92, textCardW - 32, "LEFT") end,
            get = function() return CurrentSlot(kind) end,
            set = function(v)
                SetCurrentSlot(kind, v)
                FocusGFPreviewText(kind, v, true)
                RequestGroupBarsRefresh(ctx, "gf-bars-text-slot")
            end },
        { "dropdown", "mode", nil, { cfg.valueLabel or "Value", cfg.baseModes or cfg.modes or TEXT_MODES, textCardW - 32 },
            { 16, -154, textCardW - 32, "LEFT" }, path = path .. "slot.mode",
            get = function()
                local mode = CurrentMode()
                return hasAbsorb and M.UnitSectionsShared.HealthBaseMode(mode) or mode
            end,
            set = function(value)
                local spec, oldMode = SelectedSlotSpec(), CurrentMode()
                local mode = value or spec.default
                if hasAbsorb and M.UnitSectionsShared.HealthModeHasAbsorb(oldMode) and M.UnitSectionsShared.HealthModeSupportsAbsorb(mode) then
                    mode = M.UnitSectionsShared.HealthModeWithAbsorb(mode, true)
                end
                Set(CurrentScope(), spec.key, mode, "visual")
                AfterModeChanged(mode)
            end },
    }
    if hasAbsorb then
        rows[#rows + 1] = { "segment", "absorb", nil, { "Absorb", ABSORB_STYLE_VALUES, textCardW - 32 }, path = path .. "slot.absorb",
            beforeBind = function(widget) W.MoveWidget(widget, content, 16, -216, textCardW - 32, "LEFT") end,
            get = function()
                if not M.UnitSectionsShared.HealthModeHasAbsorb(CurrentMode()) then return "off" end
                local spec = SelectedSlotSpec()
                return Bool(CurrentScope(), spec.absorbIconKey, Bool(CurrentScope(), cfg.absorbIconKey, false)) and "icon" or "value"
            end,
            set = function(value)
                local spec = SelectedSlotSpec()
                local mode = M.UnitSectionsShared.HealthModeWithAbsorb(CurrentMode(), value ~= "off")
                Set(CurrentScope(), spec.key, mode, "visual")
                if value ~= "off" then Set(CurrentScope(), spec.absorbIconKey, value == "icon", "font") end
                AfterModeChanged(mode)
            end }
    end
    rows[#rows + 1] = { "toggle", "hidePercent", nil, { "Hide % sign", 16, hasAbsorb and -278 or -216, textCardW - 32 }, path = path .. "slot.hide_percent",
        get = function()
            local spec = SelectedSlotSpec()
            return spec.hidePercentKey and SlotHidePercentSymbol(CurrentScope(), spec.hidePercentKey) or false
        end,
        set = function(value)
            local spec = SelectedSlotSpec()
            if spec.hidePercentKey then Set(CurrentScope(), spec.hidePercentKey, value and true or false, "visual") end
            FocusGFPreviewText(kind, CurrentSlot(kind), true)
            RequestGroupBarsRefresh(ctx, "gf-bars-text-hide-percent-symbol")
        end }
    Schema.Build(ctx, content, rows, ROW_OPTIONS, controls)
    function controls.RefreshPercentToggles(enabled)
        SetOptionEnabled(controls.hidePercent, enabled == true and TextModeHasPercent(CurrentMode()))
    end
    function controls.RefreshAbsorbControl(enabled)
        if controls.absorb then
            SetOptionEnabled(controls.absorb, enabled == true and M.UnitSectionsShared.HealthModeSupportsAbsorb(CurrentMode()))
        end
    end
    return controls, content, path
end
local function ValueTabFormatPosition(ctx, s, kind, tab, cfg, controls, content, path)
    local textCardW, textRightX, textRightW = s.textCardW, s.textRightX, s.textRightW
    local hpSliderW, textHalfDropW = s.hpSliderW, s.textHalfDropW
    local PlaceSlider = UnitSectionShared.PlaceSlider
    local slots = s.slots
    local CurrentSlot, SlotFontSizeKey = slots.CurrentSlot, slots.SlotFontSizeKey
    local MoveTogether, SetMoveTogether = slots.MoveTogether, slots.SetMoveTogether
    local formattingY = cfg.absorbIconKey ~= nil and -310 or -248
    local formattingRows = {
        { "text", "formatting", nil, { "Formatting", 16, formattingY, textCardW - 32, T.colors.text },
            scope = "group", meta = { controlId = path .. "formatting" } },
        { "dropdown", cfg.delimiterKey, " / ", { "Delimiter", DELIMITER_VALUES, textHalfDropW },
            { 16, formattingY - 28, textHalfDropW, "LEFT" } },
    }
    if cfg.reverseKey then formattingRows[#formattingRows + 1] =
        { "toggle", cfg.reverseKey, false, { "Reverse order", 28 + textHalfDropW, formattingY - 50, textHalfDropW } } end
    if cfg.decimalsKey then formattingRows[#formattingRows + 1] =
        { "toggle", cfg.decimalsKey, false, { "Decimal percent", 28 + textHalfDropW, formattingY - 78, textHalfDropW } } end
    if cfg.shortNumbersKey then formattingRows[#formattingRows + 1] =
        { "toggle", cfg.shortNumbersKey, true, { "Short numbers", 16, formattingY - 78, textHalfDropW }, domain = "font" } end
    local formatting = Schema.Build(ctx, content, formattingRows, ROW_OPTIONS)
    controls.delimiter, controls.reverse = formatting[cfg.delimiterKey], formatting[cfg.reverseKey]
    controls.decimals, controls.shortNumbers = formatting[cfg.decimalsKey], formatting[cfg.shortNumbersKey]
    if cfg.shortNumbersKey then
        function controls.RefreshShortNumbersToggle(enabled)
            local hasNumericValue = false
            for _, spec in pairs(cfg.slots or {}) do
                local mode = Val(CurrentScope(), spec.key, spec.default)
                if mode ~= "NONE" and mode ~= "PERCENT" then
                    hasNumericValue = true
                    break
                end
            end
            SetOptionEnabled(controls.shortNumbers, enabled == true and hasNumericValue)
        end
    end
    local position = Schema.Build(ctx, tab, {
        { "card", path .. "position", nil, { "Position", cfg.positionSubtitle, textRightX, -4, textRightW, 220 }, scope = "group" },
    })[path .. "position"]
    Schema.Build(ctx, position, {
        { "toggle", "moveTogether", nil, { "Move text as one group", 16, -64, textRightW - 32 },
            path = path .. "move_together", classification = "ephemeral", domain = "menuState",
            get = function() return MoveTogether(kind) end,
            set = function(v)
                SetMoveTogether(kind, v)
                local selectedValue1
                if not (v) then selectedValue1 = CurrentSlot(kind) end
                FocusGFPreviewText(kind, selectedValue1, true)
                if M.RefreshGFNativePreviews then M.RefreshGFNativePreviews() end
                RequestGroupBarsRefresh(ctx, "gf-bars-text-move-together")
            end },
        { "slider", "slotSize", cfg.sizeDefault, { "Selected slot size", 6, 48, 1, hpSliderW }, path = path .. "slot.size", domain = "font", roundStep = true,
            beforeBind = function(widget) PlaceSlider(position, widget, 16, -122, textRightW - 58) end,
            get = function()
                local value = tonumber(Val(CurrentScope(), SlotFontSizeKey(kind), nil))
                return value and value > 0 and value or tonumber(Val(CurrentScope(), cfg.sizeKey, cfg.sizeDefault)) or cfg.sizeDefault
            end,
            set = function(v)
                Set(CurrentScope(), SlotFontSizeKey(kind), v, "font")
                FocusGFPreviewText(kind, CurrentSlot(kind), true)
            end },
    }, ROW_OPTIONS, controls)
end
local function BuildGFValueTextTab(ctx, s, kind, tab, cfg)
    local controls, content, path = ValueTabSlots(ctx, s, kind, tab, cfg)
    ValueTabFormatPosition(ctx, s, kind, tab, cfg, controls, content, path)
    return controls
end
local function GFTextValueTabs(ctx, s)
    local HP_BASE_MODES = M.UnitSectionsShared.HealthBaseModeValues(HEALTH_TEXT_MODES)
    for _, tab in ipairs({
        { "hp", "HP value", "Show HP Text", "text", "hpText", "hpFontSize", 10, "textDelimiter" },
        { "power", "Power value", "Show Power Text", "powerText", "powerText", "powerFontSize", 9, "powerTextDelimiter" },
    }) do
        local kind, slots = tab[1], {}
        for _, slot in ipairs({ { "left", "Left", "NONE" }, { "center", "Center", "PERCENT" }, { "right", "Right", "NONE" } }) do
            slots[slot[1]] = {
                key = tab[4] .. slot[2], default = slot[3], hidePercentKey = tab[5] .. slot[2] .. "HidePercentSymbol",
                absorbIconKey = kind == "hp" and tab[5] .. slot[2] .. "AbsorbIcon" or nil,
            }
        end
        local cfg = {
            valueLabel = tab[2], showLabel = tab[3], slots = slots, sizeKey = tab[6], sizeDefault = tab[7], delimiterKey = tab[8],
            positionSubtitle = "Move the group or selected slot directly in Preview.",
        }
        if kind == "hp" then
            cfg.modes, cfg.baseModes, cfg.showKey, cfg.showDefault = HEALTH_TEXT_MODES, HP_BASE_MODES, "showHPText", true
            cfg.reverseKey, cfg.decimalsKey = "hpTextReverse", "healthTextDecimals"
            cfg.shortNumbersKey, cfg.absorbIconKey = "hpFullValueShort", "hpAbsorbIcon"
        else
            cfg.showGet = IsPowerTextEnabled
            cfg.showSet = function(v)
                SetPowerTextEnabled(v)
                if s.refresh then s.refresh() end
            end
        end
        s[kind .. "Controls"] = BuildGFValueTextTab(ctx, s, kind, s[kind .. "Tab"], cfg)
    end
end
local function GFTextAdvancedTab(ctx, s)
    local c = {}
    local textLeftX, textCardW, textSliderW = s.textLeftX, s.textCardW, s.textSliderW
    local advancedLayers = Schema.Build(ctx, s.advancedTab, {
        { "card", "textLayers", nil, { "Text Layers", "Controls text layers when text overlaps bars, icons, or indicators.",
            textLeftX, -4, textCardW, 260 }, scope = "group" },
    }).textLayers
    Schema.Build(ctx, advancedLayers, {
        { "slider", "nameTextLayer", 5, { "Name layer", 0, 30, 1, textSliderW }, { 16, -76, textCardW - 72, "CENTER" }, domain = "font" },
        { "slider", "textLayer", 5, { "HP layer", 0, 30, 1, textSliderW }, { 16, -136, textCardW - 72, "CENTER" }, domain = "font" },
        { "slider", "powerTextLayer", 2, { "Power layer", 0, 30, 1, textSliderW }, { 16, -196, textCardW - 72, "CENTER" }, domain = "font" },
    }, ROW_OPTIONS, c)
    s.nameLayer, s.hpLayer, s.powerLayer = c.nameTextLayer, c.textLayer, c.powerTextLayer
end
local function GFTextRefresh(ctx, s)
    local text, slots = s.text, s.slots
    local hpControls, powerControls = s.hpControls, s.powerControls
    local showName, hideNameOnStatus, nameAnchor, nameSize = s.showName, s.hideNameOnStatus, s.nameAnchor, s.nameSize
    local nameLayer, hpLayer, powerLayer = s.nameLayer, s.hpLayer, s.powerLayer
    local CurrentSlot, MoveTogether, RefreshTextTabs = slots.CurrentSlot, slots.MoveTogether, s.RefreshTextTabs
    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookGFPreviewTextFocus(s, controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showName }, { hideNameOnStatus }, { nameAnchor }, { nameSize }, { nameLayer } })
    local nameTextControls = { hideNameOnStatus, nameSize, nameAnchor, nameLayer }
    local hpTextControls, hpSlotControls = M.UnitSectionsShared.ValueTextControlSets("hp", hpControls, hpLayer, HookTextControls, CurrentSlot)
    local powerTextControls, powerSlotControls = M.UnitSectionsShared.ValueTextControlSets("power", powerControls, powerLayer, HookTextControls, CurrentSlot)
    if hpControls.decimals then hpTextControls[#hpTextControls + 1] = hpControls.decimals end
    if hpControls.shortNumbers then hpTextControls[#hpTextControls + 1] = hpControls.shortNumbers end
    s.refresh = function()
        local tab = CurrentTextTab()
        local nameOn = Bool(CurrentScope(), "showName", true)
        local hpOn = Bool(CurrentScope(), "showHPText", true)
        local powerOn = IsPowerTextEnabled()
        RefreshTextTabs()
        SetOptionsEnabled(nameTextControls, nameOn)
        SetOptionsEnabled(hpTextControls, hpOn)
        if hpControls.RefreshPercentToggles then hpControls.RefreshPercentToggles(hpOn) end
        if hpControls.RefreshAbsorbControl then hpControls.RefreshAbsorbControl(hpOn) end
        if hpControls.RefreshShortNumbersToggle then hpControls.RefreshShortNumbersToggle(hpOn) end
        SetOptionsEnabled(hpSlotControls, hpOn and not MoveTogether("hp"))
        SetOptionsEnabled(powerTextControls, powerOn)
        if powerControls.RefreshPercentToggles then powerControls.RefreshPercentToggles(powerOn) end
        SetOptionsEnabled(powerSlotControls, powerOn and not MoveTogether("power"))
        SetOptionEnabled(showName, true)
        SetOptionEnabled(hpControls.show, true)
        SetOptionEnabled(powerControls.show, true)
        local kind = CurrentScope()
        if hpControls.preview then
            local delim = Val(kind, "textDelimiter", " / ")
            hpControls.preview:SetText(BuildTextPreviewStr(
                Val(kind, "textLeft", "NONE"), Val(kind, "textCenter", "PERCENT"), Val(kind, "textRight", "NONE"),
                delim, Bool(kind, "hpTextReverse", false), false, Bool(kind, "healthTextDecimals", false), Bool(kind, "hpFullValueShort", true),
                SlotHidePercentSymbol(kind, "hpTextLeftHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "hpTextCenterHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "hpTextRightHidePercentSymbol"),
                Bool(kind, "hpTextLeftAbsorbIcon", Bool(kind, "hpAbsorbIcon", false)),
                Bool(kind, "hpTextCenterAbsorbIcon", Bool(kind, "hpAbsorbIcon", false)),
                Bool(kind, "hpTextRightAbsorbIcon", Bool(kind, "hpAbsorbIcon", false))))
        end
        if powerControls.preview then
            local delim = Val(kind, "powerTextDelimiter", " / ")
            powerControls.preview:SetText(BuildTextPreviewStr(
                Val(kind, "powerTextLeft", "NONE"), Val(kind, "powerTextCenter", "PERCENT"), Val(kind, "powerTextRight", "NONE"),
                delim, false, true, false, true,
                SlotHidePercentSymbol(kind, "powerTextLeftHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "powerTextCenterHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "powerTextRightHidePercentSymbol")))
        end
        UpdateTextHeaderBadges(s, tab, nameOn, hpOn, powerOn)
        FocusActiveGFPreviewText(s)
    end
    TrackSectionRefresh(ctx, text, s.refresh)
end

local function BuildGFTextSection(ctx, b)
    local s = GFTextLayout(b)
    GFTextState(s)
    GFTextTabs(ctx, s)
    GFTextNameTab(ctx, s)
    GFTextValueTabs(ctx, s)
    GFTextAdvancedTab(ctx, s)
    GFTextRefresh(ctx, s)
end

local function BuildGFDebuffStripeSection(ctx, b)
    local c = {}
    local stripe = Schema.Section(b:CollapsibleSection("dstripe", "Debuff Stripe", 284, false), "group")
    local stripeW = stripe._msuf2Width or b.width or 720
    local stripeCardW = min(560, stripeW - 40)
    local stripeCard = Schema.Build(ctx, stripe, {
        { "card", "stripeCard", nil, { "Appearance & Placement", "Shows a thin colored stripe for debuffs matched by the debuff filter.",
            20, -38, stripeCardW, 216 }, scope = "group" },
    }).stripeCard
    Schema.Colors(stripeCard, { "group.debuff_stripe" }, {
        title = "Debuff Stripe Color",
        note = "Shared by Party, Raid and Mythic Raid.",
        historySource = "menu:group-debuff-stripe-color",
        offsetX = -76,
    })
    Schema.Build(ctx, stripeCard, {
        { "sectionSwitch", "debuffStripeEnabled", false, { "Debuff Stripe" }, parent = stripe },
        { "dropdown", "debuffStripeEdge", "BOTTOM", { "Stripe edge", DEBUFF_STRIPE_EDGES, 260 }, { 16, -74, min(260, stripeCardW - 32), "LEFT" } },
        { "slider", "debuffStripeHeight", 3, { "Stripe height", 1, 8, 1, 300 }, { 16, -126, min(360, stripeCardW - 72), "CENTER" } },
        { "text", "stripeHint", nil, { "", 16, -176, stripeCardW - 32, T.colors.muted }, scope = "group",
            beforeBind = function(widget, row)
                local text = M.Format("Color and opacity are in %s.", M.NavPath("opt_colors", "Party & Raid Frames"))
                T.SetTranslatedText(widget, text)
                W._Shared.SetSearchText(widget, text)
                M.RegisterSearchWidget(widget, { label = text, kind = "text" })
                row[4][1] = text
            end },
    }, ROW_OPTIONS, c)
    if c.stripeHint.SetWordWrap then c.stripeHint:SetWordWrap(true) end
    local stripeControls = { c.debuffStripeEdge, c.debuffStripeHeight }
    local function RefreshStripeState()
        local enabled = Bool(CurrentScope(), "debuffStripeEnabled", false)
        SetOptionsEnabled(stripeControls, enabled)
        SetOptionEnabled(c.debuffStripeEnabled, true)
        SetSectionBadgesAndStatus(stripe, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = OptionText(DEBUFF_STRIPE_EDGES, Val(CurrentScope(), "debuffStripeEdge", "BOTTOM"), "Bottom Edge"), kind = enabled and "info" or "muted" },
            { text = M.Format("%s px", BadgeNumber(Num(CurrentScope(), "debuffStripeHeight", 3))), kind = enabled and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, stripe, RefreshStripeState)
end

local function BuildGFRangeFadeSection(ctx, b)
    local c = {}
    local AlphaLabel = M.AlphaLabel
    -- 220 mirrors the registered section height in MSUF_Menu2_GroupLayout; the
    -- lazy shell wins over this call, so a larger value here only desynced the
    -- non-lazy fallback path from what the page actually renders.
    local range = b:CollapsibleSection("range", "Range Fade", 220, false)
    if not range._msuf2CollapsibleEntry.header._msuf2ControlSchema then Schema.Section(range, "group") end
    local rangeLeftX, rangeLeftWidth, rangeRightX, rangeRightWidth = Schema.Columns(range, range._msuf2Width or b.width or 720, 20, 16, 0.48)
    -- Both cards sit at -18 so the 190pt card body ends 12pt above the section
    -- floor instead of overflowing it by 8pt while leaving a dead band under
    -- the accordion header.
    local rangeCardY = -18
    Schema.Build(ctx, range, {
        { "card", "rangeEffect", nil, { "Behavior", nil, rangeLeftX, rangeCardY, rangeLeftWidth, 190 }, scope = "group" },
        { "card", "rangeAlpha", nil, { "Alpha", "Opacity values used by range and offline states.", rangeRightX, rangeCardY,
            rangeRightWidth, 190 }, scope = "group" },
    }, nil, c)
    local rangeEffectCard, rangeAlphaCard = c.rangeEffect, c.rangeAlpha
    local rangeToggle = PrepareRangeSwitch(ctx, range)
    local function BindRangeAlphaSlider(key, label, default, y)
        -- The live label names the slider on screen; search needs it as the label.
        local function LabelMeta()
            local meta = ControlMeta(ctx, "field." .. tostring(key))
            meta.label = label
            return meta
        end
        local control = Schema.Build(ctx, rangeAlphaCard, {
            { "slider", key, default, { "", 0, 1, 0.05, rangeRightWidth },
                get = function() return Num(CurrentScope(), key, default) end,
                set = function(v)
                    local n = tonumber(v) or default or 0
                    local conf = Conf(CurrentScope())
                    if conf[key] == n then return end
                    conf[key] = n
                    QueueGF(CurrentScope(), "visual")
                end },
        }, Schema.GroupCommands({}, LabelMeta, LabelMeta))[key]
        if key == "rangeFadeAlpha" and M.BindSliderDragPreview and M.SetRangeFadePreviewState then
            M.BindSliderDragPreview(control, function(active, value)
                M.SetRangeFadePreviewState("group", active, value,
                    Val(CurrentScope(), "rangeFadeLayerMode", "frame"))
            end)
        end
        W.MoveWidget(control, rangeAlphaCard, 16, y, rangeRightWidth - 58, "CENTER")
        return M.BindSliderLiveLabel(ctx, control, function() return Num(CurrentScope(), key, default) end,
            function(value) return AlphaLabel(label, tonumber(value) or default or 0) end, true)
    end
    local rangeModeW = min(240, rangeLeftWidth - 32)
    -- Rows mirror the alpha card on the right: -70 lines up with "Out of range",
    -- -122 with "Offline", so both cards read as one grid instead of a gap plus
    -- a segment overlapping the offline toggle.
    Schema.Build(ctx, rangeEffectCard, {
        { "segment", "rangeMode", nil, { "Affects", VT("frame", "Frame", "health", "HP"), rangeModeW }, { 16, -70, rangeModeW, "LEFT" },
            path = "field.rangeFadeLayerMode",
            get = function() return Val(CurrentScope(), "rangeFadeLayerMode", "frame") end,
            set = function(v) Set(CurrentScope(), "rangeFadeLayerMode", v or "frame", "visual") end },
        { "toggle", "offlineFadeEnabled", false, { "Fade offline members", 16, -122, rangeLeftWidth - 32 } },
        { "text", "offlineHint", nil, { "Hiding offline members in Basics takes precedence over this.", 16, -154, rangeLeftWidth - 32,
            T.colors.muted }, scope = "group" },
    }, ROW_OPTIONS, c)
    if c.offlineHint and c.offlineHint.SetWordWrap then c.offlineHint:SetWordWrap(true) end
    local rangeControls = {
        c.rangeMode,
        BindRangeAlphaSlider("rangeFadeAlpha", "Out of range", 0.4, -70),
    }
    -- Offline opacity is independent of range fade: it drives the fade state and
    -- doubles as the transition value while the Basics hide delay runs.
    local offlineAlphaSlider = BindRangeAlphaSlider("offlineAlpha", "Offline", 0.5, -124)
    local function RefreshRangeState()
        local enabled = Bool(CurrentScope(), "rangeFadeEnabled", false)
        local offlineFade = Bool(CurrentScope(), "offlineFadeEnabled", false)
        local offlineHidden = Bool(CurrentScope(), "hideOfflineEnabled", false)
        SetOptionsEnabled(rangeControls, enabled)
        SetOptionEnabled(rangeToggle, true)
        SetOptionEnabled(c.offlineFadeEnabled, not offlineHidden)
        SetOptionEnabled(offlineAlphaSlider, offlineFade or offlineHidden)
        local offlineText, offlineKind = "Offline visible", "muted"
        if offlineHidden then
            offlineText, offlineKind = "Offline hidden", "accent"
        elseif offlineFade then
            offlineText = M.Format("Offline %d%%", floor(Num(CurrentScope(), "offlineAlpha", 0.5) * 100 + 0.5))
            offlineKind = "accent"
        end
        SetSectionBadgesAndStatus(range, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = Val(CurrentScope(), "rangeFadeLayerMode", "frame") == "health" and "HP only" or "Whole frame", kind = enabled and "info" or "muted" },
            { text = tostring(floor(Num(CurrentScope(), "rangeFadeAlpha", 0.4) * 100 + 0.5)) .. "%", kind = enabled and "accent" or "muted" },
            { text = offlineText, kind = offlineKind },
        })
    end
    TrackSectionRefresh(ctx, range, RefreshRangeState)
end

M.GroupFrameLayoutSections = M.GroupFrameLayoutSections or {}
M.GroupFrameLayoutSections.PreparePowerSwitch = PreparePowerSwitch
M.GroupFrameLayoutSections.PrepareRangeSwitch = PrepareRangeSwitch
M.GroupFrameLayoutSections.BuildResourceBar = BuildGFResourceBarSection
M.GroupFrameLayoutSections.BuildText = BuildGFTextSection
M.GroupFrameLayoutSections.BuildRangeFade = BuildGFRangeFadeSection

local function BuildGFBars(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    BuildDispelOverlaySection(ctx, b)
    BuildGFDispelSymbolSection(ctx, b)
    BuildGFDebuffStripeSection(ctx, b)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_bars", { title = "MSUF Group Dispel Overlay", build = BuildGFBars, version = 22 })
