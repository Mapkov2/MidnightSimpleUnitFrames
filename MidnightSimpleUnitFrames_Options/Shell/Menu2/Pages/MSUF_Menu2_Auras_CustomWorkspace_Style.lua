-- Custom Aura style tools; retains the shared per-build container context.
local _, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.CustomAuraWorkspaceParts
local HideInlineSwatch = Parts.HideInlineSwatch
local W = Parts.W
local T = Parts.T
local A3 = Parts.A3
local Model = Parts.Model
local AurasPage = Parts.AurasPage
local floor = Parts.floor
local ceil = Parts.ceil
local max = Parts.max
local min = Parts.min
local tonumber = Parts.tonumber
local tostring = Parts.tostring
local type = Parts.type
local BindSwitch = Parts.BindSwitch
local BindSlider = Parts.BindSlider
local BindDropdown = Parts.BindDropdown
local AURA_COOLDOWN_COLOR_REFERENCES = Parts.AURA_COOLDOWN_COLOR_REFERENCES
local AURA_SORT_DIRECTION_VALUES = Parts.AURA_SORT_DIRECTION_VALUES
local AddAuraTooltipHelp = Parts.AddAuraTooltipHelp
local AddTooltip = Parts.AddTooltip
local AnchorLabel = Parts.AnchorLabel
local AuraCatalogToken = Parts.AuraCatalogToken
local AuraControlMeta = Parts.AuraControlMeta
local AuraControlMetaAtVisiblePath = Parts.AuraControlMetaAtVisiblePath
local AuraSortMethodValues = Parts.AuraSortMethodValues
local COOLDOWN_SWIPE_DIRECTION_VALUES = Parts.COOLDOWN_SWIPE_DIRECTION_VALUES
local CUSTOM_FRAME_EFFECTS = Parts.CUSTOM_FRAME_EFFECTS
local ChoiceLabel = Parts.ChoiceLabel
local ConfigureMaxDurationSlider = Parts.ConfigureMaxDurationSlider
local DEBUFF_TYPE_BORDER_MODE_VALUES = Parts.DEBUFF_TYPE_BORDER_MODE_VALUES
local DURATION_BAR_DIRECTION_VALUES = Parts.DURATION_BAR_DIRECTION_VALUES
local DURATION_BAR_DISPLAY_VALUES = Parts.DURATION_BAR_DISPLAY_VALUES
local DURATION_BAR_POSITION_VALUES = Parts.DURATION_BAR_POSITION_VALUES
local NormalizeAuraSortMethodForLane = Parts.NormalizeAuraSortMethodForLane
local QueueAurasPageRefresh = Parts.QueueAurasPageRefresh
local Round = Parts.Round
local Tr = Parts.Tr
local CustomStyleSectionId = Parts.CustomStyleSectionId
local REMINDERS_AVAILABLE = Parts.REMINDERS_AVAILABLE
local TRANSLATED_TITLE = Parts.TRANSLATED_TITLE
local ContainerTitle = Parts.ContainerTitle

local function BuildCustomFiltersTool(C)
    local ctx, b, tool, isPlayerDefensives, isTargetDots, item, Apply, Grid = C.ctx, C.b, C.tool, C.isPlayerDefensives, C.isTargetDots, C.item, C.Apply, C.Grid
    local WriteMaxDuration = { write = { container = C, source = function() return item end,
                convert = function(value) return Round(min(180, max(0, tonumber(value) or 0))) end,
                after = function() Apply("AURAS3_CUSTOM_MAX_DURATION", true) end
            } --[[schema setter: J5.CustomStyle.1]] }

    if tool == "filters" then
        if isPlayerDefensives or isTargetDots then
            local section = b:Section(M.Format("%s Filters", ContainerTitle(C)), 160, TRANSLATED_TITLE)
            local w = section._msuf2Width or b.width or 720
            local inner = w - 48
            local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24, -40, inner,
                function() return item.filters.hidePermanent == true end,
                { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true) end
            } --[[schema setter: J5.CustomStyle.2]] },
                AuraControlMeta(ctx, "custom-container.filters.hide-permanent"))
            AddTooltip(hidePermanent, "Hide permanent auras",
                "Always excludes auras without a duration.")
            local maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration",
                24, -92, 0, 180, 1, inner,
                function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
                WriteMaxDuration,
                AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {})))
            M.TrackRefresh(ctx, function()
                W.SetControlEnabled(hidePermanent, true)
                W.SetControlEnabled(maxDuration, true)
            end)
            return true
        end
        local specs = item.auraType == "DEBUFF" and {
            { "Only mine", "onlyMine" }, { "Raid", "raid" }, { "Raid combat", "raidInCombat" }, { "Nameplate-only", "includeNameplateOnly" },
            { "Removable by group", "includeDispellable" }, { "Any removable type", "dispellableAny" },
            { "Important", "onlyImportant" }, { "Crowd control", "crowdControl" },
        } or {
            { "Only mine", "onlyMine" }, { "Important", "onlyImportant" }, { "Raid", "raid" }, { "Raid combat", "raidInCombat" }, { "Nameplate-only",
                "includeNameplateOnly" },
            { "Removable by group", "includeDispellable" }, { "Any removable type", "dispellableAny" },
            { "Cancelable", "cancelable", { "notCancelable" } }, { "Not cancelable", "notCancelable", { "cancelable" } },
            { "External defensive", "externalDefensive" }, { "Big defensive", "bigDefensive" },
        }
        local optionRows = max(1, ceil(#specs / 4))
        local section = b:Section(M.Format("%s Filters", ContainerTitle(C)), 160 + optionRows * 32, TRANSLATED_TITLE)
        local w = section._msuf2Width or b.width or 720
        local colW, gap = Grid(w, 4)
        local controls = {}
        local master = BindSwitch(ctx, section, "Enable filters", 24, -40, colW,
            function() return item.filters.enabled ~= false end,
            { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_FILTER_ENABLE", true) end
            } --[[schema setter: J5.CustomStyle.3]] },
            AuraControlMeta(ctx, "custom-container.filters.enabled"))
        local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -40, colW,
            function() return item.filters.hidePermanent == true end,
            { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true) end
            } --[[schema setter: J5.CustomStyle.4]] },
            AuraControlMeta(ctx, "custom-container.filters.hide-permanent"))
        AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration. It remains active when token filters are disabled.")
        for i = 1, #specs do
            local spec = specs[i]
            local col = (i - 1) % 4
            local row = floor((i - 1) / 4)
            local control = BindSwitch(ctx, section, spec[1], 24 + col * (colW + gap), -76 - row * 32, colW,
                function()
                    if spec[2] == "raid" and item.filters.exclusive == "raid" then return true end
                    return item.filters[spec[2]] == true
                end,
                function(value)
                    if spec[2] == "raid" then item.filters.exclusive = nil end
                    item.filters[spec[2]] = value == true
                    if value == true and spec[3] then for j = 1, #spec[3] do item.filters[spec[3][j]] = false end end
                    Apply("AURAS3_CUSTOM_FILTER")
                    if spec[3] then QueueAurasPageRefresh(ctx, "custom-filter-conflict") end
                end,
                AuraControlMeta(ctx, "custom-container.filters." .. AuraCatalogToken(spec[2])))
            controls[#controls + 1] = control
        end
        local maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24,
            -76 - optionRows * 32, 0, 180, 1, w - 48,
            function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
            WriteMaxDuration,
            AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {})))
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(master, true)
            W.SetControlEnabled(hidePermanent, true)
            W.SetControlEnabled(maxDuration, true)
            W.SetControlsEnabled(controls, item.filters.enabled ~= false)
        end)
        return true
    end
end

local function BuildCustomLayoutTool(C)
    local ctx, b, unit, tool, item, Apply, Grid = C.ctx, C.b, C.unit, C.tool, C.item, C.Apply, C.Grid
    if tool == "layout" then
        local layoutTitle = M.Format("%s Layout", ContainerTitle(C))
        local section = b:Section(layoutTitle, 190, TRANSLATED_TITLE)
        M.AttachAuraFontsAndColors(section, layoutTitle, unit)
        local w = section._msuf2Width or b.width or 720
        local col3, gap3 = Grid(w, 3)
        BindDropdown(ctx, section, "Anchor", 24, -34, Model.AuraAnchorValues(), col3,
            function() return item.placed.anchor or "TOPRIGHT" end,
            { write = { container = C, source = function() return item end,
                fallback = "TOPRIGHT", after = function() Apply("AURAS3_CUSTOM_ANCHOR") end
            } --[[schema setter: J5.CustomStyle.5]] },
            AuraControlMeta(ctx, "custom-container.layout.anchor"))
        BindDropdown(ctx, section, "Growth", 24 + col3 + gap3, -34, Model.LaneGrowthValues(), col3,
            function() return item.placed.growth or "LEFTDOWN" end,
            { write = { container = C, source = function() return item end,
                fallback = "LEFTDOWN", after = function() Apply("AURAS3_CUSTOM_GROWTH", true) end
            } --[[schema setter: J5.CustomStyle.6]] },
            AuraControlMeta(ctx, "custom-container.layout.growth"))
        local col4, gap4 = Grid(w, 4)
        local values = {
            { "Max", "max", 0, 40, 8 }, { "Size", "size", 8, 128, 24 },
            { "Per row", "perRow", 1, 20, 4 }, { "Gap", "spacing", 0, 24, 2 }, { "Layer (0-30)", "layer", 0, 30, 9 },
        }
        local perRowControl
        for i = 1, #values do
            local spec = values[i]
            local row = i <= 4 and 0 or 1
            local col = row == 0 and (i - 1) or (i - 5)
            local routeContract
            if spec[2] == "layer" then
                local layerSettingKeys = {}
                for customIndex = 1, 4 do
                    layerSettingKeys[#layerSettingKeys + 1] =
                        "auras3." .. tostring(unit) .. ".custom" .. tostring(customIndex) .. ".layer"
                end
                routeContract = {
                    searchSettingKeys = layerSettingKeys,
                }
            end
            local control = BindSlider(ctx, section, spec[1], 24 + col * (col4 + gap4), row == 0 and -92 or -146, spec[3], spec[4], 1, col4,
                function() return tonumber(spec[2] == "layer" and item.layer or item.placed[spec[2]]) or spec[5] end,
                { write = { container = C, source = function() return item end,
                    convert = function(value)
                        if spec[2] == "layer" then return floor(tonumber(value) or spec[5]) end
                        return tonumber(value) or spec[5]
                    end,
                    after = function() Apply("AURAS3_CUSTOM_" .. spec[2]:upper()) end
                } --[[schema setter: J5.CustomStyle.LayoutFields]] },
                AuraControlMeta(ctx, "custom-container.layout." .. AuraCatalogToken(spec[2]), nil, routeContract))
            if spec[2] == "perRow" then perRowControl = control end
        end
        M.TrackRefresh(ctx, function()
            local growth = tostring(item.placed.growth or "LEFTDOWN"):upper()
            W.SetControlEnabled(perRowControl, growth ~= "UP" and growth ~= "DOWN")
        end)
        W.Text(section, "Position is controlled by the colored aura handle in Preview.", 24 + col4 + gap4, -154, col4 * 3 + gap4 * 2, T.colors.muted)
        return true
    end
end

-- Pandemic is a native aura-backend feature: the applier below and Blizzard's
-- AddPandemicRegion button method both arrive with the native 12.1 runtime, so a
-- backend that publishes no applier can never show the state. Ask the backend for
-- the capability instead of the client, the same test the aura previews use, so
-- the section follows whichever backend a flavor loads.
local function PandemicVisualSupported()
    return A3.ApplyPandemicVisual
end
-- Every Custom container, including Player Defensives and Dots on Target,
-- binds its visual controls to the UnitFrame-owned style record. A Style
-- accordion lays them out on a four-column grid: StyleGrid returns its column
-- width, its column x and its number-row constructor.
local function StyleGrid(C, section)
    local ctx, Apply, item = C.ctx, C.Apply, C.styleItem
    local w = section._msuf2Width or C.b.width or 720
    local col4, gap = C.Grid(w, 4)
    local function X(col) return 24 + (col - 1) * (col4 + gap) end
    local function Number(label, col, y, minValue, maxValue, key, fallback, afterSet)
        return BindSlider(ctx, section, label, X(col), y, minValue, maxValue, 1, col4,
            function() return tonumber(item.placed[key]) or fallback end,
            { write = { container = C, source = function() return item end,
                numberDefault = fallback, after = function() Apply("AURAS3_CUSTOM_APPEARANCE_" .. key:upper()) if afterSet then afterSet() end end
            } --[[schema setter: J5.CustomStyle.7]] },
            AuraControlMeta(ctx, "custom-container.appearance." .. AuraCatalogToken(key)))
    end
    return col4, X, Number
end
local function GateControls(ctx, readEnabled, controls)
    M.TrackRefresh(ctx, function() W.SetControlsEnabled(controls, readEnabled()) end)
end
local function BuildCustomAppearancePandemic(C)
    local ctx, b, index, isTargetDots, Apply = C.ctx, C.b, C.index, C.isTargetDots, C.Apply
    local item = C.styleItem
    local pandemic
    if isTargetDots and PandemicVisualSupported() then
        pandemic = AurasPage.Section(b, CustomStyleSectionId(index, "pandemic"), "Pandemic Warning & Style", 248, false)
        local pandemicCol, pandemicX, PandemicNumber = StyleGrid(C, pandemic)
        local pandemicControls = {}
        local pandemicWarning = W.Text(pandemic,
            "PERFORMANCE NOTE: On 12.1.0 Blizzard runs an OnUpdate every frame on each visible aura button for the full aura while it has a calculated "
                .. "pandemic window, not only while the warning is shown; enable it there only if you accept that combat cost. 12.1.5 and WoW Forever switch "
                .. "the window with a native timer instead, at no per-frame cost.",
            24, -96, (pandemic._msuf2Width or b.width or 720) - 48, { 1.00, 0.38, 0.18, 1 })
        if pandemicWarning.SetWordWrap then pandemicWarning:SetWordWrap(true) end
        local RefreshPandemicState
        local pandemicToggle = BindSwitch(ctx, pandemic, "Show Pandemic State", pandemicX(1), -42,
            pandemicCol, function() return item.placed.pandemicEnabled == true end,
            { write = { container = C, source = function() return item end, strictBoolean = true,
                after = function()
                    Apply("AURAS3_TARGET_DOT_PANDEMIC", true)
                    if RefreshPandemicState then RefreshPandemicState() end
                end
            } --[[schema setter: J5.CustomStyle.PandemicEnabled]] },
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.enabled"))
        AddTooltip(pandemicToggle, "12.1 Pandemic state",
            "Disabled by default. On 12.1.0 Blizzard's native implementation enables a per-frame OnUpdate for each visible aura button as soon as that aura "
                .. "has a calculated pandemic window; this can begin before the warning becomes visible. 12.1.5 and WoW Forever use a native timer instead.")
        pandemicControls[#pandemicControls + 1] = BindDropdown(ctx, pandemic, "Style", pandemicX(2), -42,
            M.AURA_PANDEMIC_STYLE_VALUES, pandemicCol,
            function() return item.placed.pandemicStyle or "BORDER" end,
            { write = { container = C, source = function() return item end,
                fallback = "BORDER", after = function() Apply("AURAS3_TARGET_DOT_PANDEMIC_STYLE", true) end
            } --[[schema setter: J5.CustomStyle.8]] },
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.style"))
        pandemicControls[#pandemicControls + 1] = BindDropdown(ctx, pandemic, "Blend", pandemicX(3), -42,
            M.AURA_PANDEMIC_BLEND_VALUES, pandemicCol,
            function() return item.placed.pandemicBlend or "ADD" end,
            { write = { container = C, source = function() return item end,
                convert = function(value) return value == "BLEND" and "BLEND" or "ADD" end,
                after = function() Apply("AURAS3_TARGET_DOT_PANDEMIC_BLEND", true) end
            } --[[schema setter: J5.CustomStyle.9]] },
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.blend"))
        -- The ::: shortcut is the section's only visible way into the color picker,
        -- so this swatch is never laid out. It still exists and stays bound: it is
        -- the control the Search and menu search resolve for this setting, and
        -- unlike the status text colors there is no Colors page surface carrying a
        -- per-custom-container pandemic color to fall back to.
        -- Attached before M.BindColor so the explicit shortcut owns the section:
        -- a shortcut generated by BindColor would be replaced by later color
        -- controls, and it could not serve as a stable search anchor.
        -- Deliberately kept out of pandemicControls: a disabled owner drops out of
        -- the shortcut's relevance check, which would make the ::: come and go with
        -- the toggle instead of staying put.
        local pandemicColor = W.Color(pandemic, "Color")
        pandemicColor._msuf2ContextColorAllowDisabled = true
        W.SetControlShown(pandemicColor, false)
        local pandemicColorShortcut
        if W.AttachContextColorShortcut then
            pandemicColorShortcut = W.AttachContextColorShortcut(pandemic, {
                historyLabel = "Pandemic color",
                historySource = "menu:custom-auras-pandemic-color",
                getTargets = function() return { pandemicColor } end,
            })
        end
        local pandemicColorMeta = AuraControlMeta(ctx, "custom-container.appearance.pandemic.color")
        -- Search must land on the shortcut; highlighting the hidden swatch would
        -- point the player at nothing.
        pandemicColorMeta.anchor = pandemicColorShortcut or nil
        AurasPage.BindColor(ctx, pandemicColor,
            function()
                local color = item.placed.pandemicColor or { 1, 0.24, 0.08 }
                return color[1] or 1, color[2] or 0.24, color[3] or 0.08
            end,
            function(r, g, blue)
                item.placed.pandemicColor = { r, g, blue }
                Apply("AURAS3_TARGET_DOT_PANDEMIC_COLOR", true)
            end,
            pandemicColorMeta)
        pandemicControls[#pandemicControls + 1] = PandemicNumber("Thickness", 1, -174, 1, 12,
            "pandemicThickness", 2)
        pandemicControls[#pandemicControls + 1] = PandemicNumber("Padding", 2, -174, -8, 16,
            "pandemicPadding", 1)
        pandemicControls[#pandemicControls + 1] = BindSlider(ctx, pandemic, "Border Opacity", pandemicX(3), -174,
            5, 100, 5, pandemicCol,
            function() return floor(((tonumber(item.placed.pandemicBorderAlpha) or 1) * 100) + 0.5) end,
            { write = { container = C, source = function() return item end,
                convert = function(value) return (tonumber(value) or 100) / 100 end,
                after = function() Apply("AURAS3_TARGET_DOT_PANDEMIC_BORDER_ALPHA", true) end
            } --[[schema setter: J5.CustomStyle.10]] },
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.border-opacity"))
        pandemicControls[#pandemicControls + 1] = BindSlider(ctx, pandemic, "Tint Opacity", pandemicX(4), -174,
            5, 100, 5, pandemicCol,
            function() return floor(((tonumber(item.placed.pandemicTintAlpha) or 0.22) * 100) + 0.5) end,
            { write = { container = C, source = function() return item end,
                convert = function(value) return (tonumber(value) or 22) / 100 end, after = function() Apply("AURAS3_TARGET_DOT_PANDEMIC_TINT_ALPHA", true) end
            } --[[schema setter: J5.CustomStyle.11]] },
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.tint-opacity"))
        RefreshPandemicState = function()
            local enabled = item.placed.pandemicEnabled == true
            W.SetControlsEnabled(pandemicControls, enabled)
            pandemicWarning:SetShown(enabled)
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(pandemic, { {
                    text = enabled and M.Format("On / %s", ChoiceLabel(M.AURA_PANDEMIC_STYLE_VALUES,
                        item.placed.pandemicStyle or "BORDER", "Border")) or Tr("Off"),
                    kind = enabled and "accent" or "muted", showWhenClosed = true,
                } })
            end
        end
        M.TrackRefresh(ctx, RefreshPandemicState)
        RefreshPandemicState()
    end
end

-- One accordion sub-section per topic, mirroring the Buff/Debuff lane style
-- sections. Search semantic paths keep the historical "appearance" segment so
-- the generated control schema stays stable.
--- Style > Basics: zoom, tooltip, opacity, lane padding and, for a harmful
--- container, the dispel-type border.
local function BuildCustomStyleBasics(C, harmfulContainer)
    local ctx, b, index, Apply = C.ctx, C.b, C.index, C.Apply
    local item = C.styleItem
    local frameBasics = AurasPage.Section(b, CustomStyleSectionId(index, "frame_basics"), "Basics", 220, true)
    local frameBasicsWidth = frameBasics._msuf2Width or b.width or 720
    local frameBasicsGap = 10
    local frameBasicsCol = max(180, floor((frameBasicsWidth - 48 - frameBasicsGap) / 2))
    local frameBasicsRightX = 24 + frameBasicsCol + frameBasicsGap
    BindSlider(ctx, frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, frameBasicsCol,
        function() return tonumber(item.placed.iconZoom) or 100 end,
        { write = { container = C, source = function() return item end,
                numberDefault = 100, after = function() Apply("AURAS3_CUSTOM_APPEARANCE_ICONZOOM") end
            } --[[schema setter: J5.CustomStyle.12]] },
        AuraControlMeta(ctx, "custom-container.appearance.icon-zoom"))
    AddAuraTooltipHelp(BindSwitch(ctx, frameBasics, "Tooltip", frameBasicsRightX, -48, frameBasicsCol,
        function() return item.placed.showTooltip ~= false end,
        { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_TOOLTIP") end
            } --[[schema setter: J5.CustomStyle.13]] },
        AuraControlMeta(ctx, "custom-container.appearance.tooltip")))
    BindSlider(ctx, frameBasics, "Opacity", 24, -106, 10, 100, 5, frameBasicsCol,
        function() return floor(((tonumber(item.placed.alpha) or 1) * 100) + 0.5) end,
        { write = { container = C, source = function() return item end,
                convert = function(value) return (tonumber(value) or 100) / 100 end, after = function() Apply("AURAS3_CUSTOM_ALPHA") end
            } --[[schema setter: J5.CustomStyle.14]] },
        AuraControlMeta(ctx, "custom-container.appearance.opacity"))
    BindSlider(ctx, frameBasics, "Lane Padding", 24, -164, 0, 16, 1, frameBasicsCol,
        function() return tonumber(item.placed.stylePadding) or 0 end,
        { write = { container = C, source = function() return item end,
                numberDefault = 0, after = function() Apply("AURAS3_CUSTOM_STYLE_PADDING") end
            } --[[schema setter: J5.CustomStyle.15]] },
        AuraControlMeta(ctx, "custom-container.appearance.style-padding"))
    if harmfulContainer then
        BindDropdown(ctx, frameBasics, "Dispel-type Border", frameBasicsRightX, -106,
            DEBUFF_TYPE_BORDER_MODE_VALUES, frameBasicsCol,
            function() return item.placed.debuffTypeBorderMode or "OFF" end,
            { write = { container = C, source = function() return item end,
                fallback = "OFF", after = function() Apply("AURAS3_CUSTOM_DEBUFF_TYPE_BORDER") end
            } --[[schema setter: J5.CustomStyle.16]] },
            AuraControlMeta(ctx, "custom-container.appearance.dispel-type-border"))
    end
    return frameBasics
end
--- Style > Stack Count: the switch and the details it gates.
local function BuildCustomStyleStack(C)
    local ctx, b, index, Apply = C.ctx, C.b, C.index, C.Apply
    local item = C.styleItem
    local stack = AurasPage.Section(b, CustomStyleSectionId(index, "stack"), "Stack Count", 130, false)
    local stackCol, stackX, StackNumber = StyleGrid(C, stack)
    BindSwitch(ctx, stack, "Stack count", stackX(1), -42, stackCol, function() return item.placed.showStacks ~= false end,
        { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_STACKS", true) end
            } --[[schema setter: J5.CustomStyle.17]] },
        AuraControlMeta(ctx, "custom-container.appearance.stack-count"))
    GateControls(ctx, function() return item.placed.showStacks ~= false end, {
        StackNumber("Stack size", 1, -76, 6, 40, "stackSize", 14),
        BindDropdown(ctx, stack, "Stack anchor", stackX(2), -76, Model.AuraAnchorValues(), stackCol,
            function() return item.placed.stackAnchor or "BOTTOMRIGHT" end,
            { write = { container = C, source = function() return item end,
                fallback = "BOTTOMRIGHT", after = function() Apply("AURAS3_CUSTOM_STACK_ANCHOR") end
            } --[[schema setter: J5.CustomStyle.18]] },
            AuraControlMeta(ctx, "custom-container.appearance.stack-anchor")),
        StackNumber("Stack X", 3, -76, -40, 40, "stackX", 0),
        StackNumber("Stack Y", 4, -76, -40, 40, "stackY", 0),
    })
    return stack
end
--- Style > Cooldown Text: text and swipe switches, their gated details and
--- the shared cooldown text color shortcut.
local function BuildCustomStyleCooldown(C)
    local ctx, b, unit, index, Apply = C.ctx, C.b, C.unit, C.index, C.Apply
    local item = C.styleItem
    local cooldown = AurasPage.Section(b, CustomStyleSectionId(index, "cooldown"), "Cooldown Text", 184, true)
    AurasPage.AttachTextColorShortcut(cooldown, unit, {
        title = M.Format("%s Cooldown Text Settings", ContainerTitle(C)),
        historyLabel = "Custom aura cooldown text color",
        historySource = "menu:custom-auras-cooldown-text-color",
    }, {
        colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
        colorTitle = M.Format("%s Cooldown Colors", ContainerTitle(C)),
        subtitle = "Custom aura text follows the shared Fonts settings.",
    })
    local cdCol, cdX, CdNumber = StyleGrid(C, cooldown)
    BindSwitch(ctx, cooldown, "Cooldown text", cdX(1), -42, cdCol, function() return item.placed.showCooldown ~= false end,
        { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_COOLDOWN", true) end
            } --[[schema setter: J5.CustomStyle.19]] },
        AuraControlMeta(ctx, "custom-container.appearance.cooldown-text"))
    BindSwitch(ctx, cooldown, "Cooldown swipe", cdX(2), -42, cdCol, function() return item.placed.showCooldownSwipe ~= false end,
        { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_SWIPE", true) end
            } --[[schema setter: J5.CustomStyle.20]] },
        AuraControlMeta(ctx, "custom-container.appearance.cooldown-swipe"))
    local customDecimal = CdNumber("Decimals below sec", 4, -76, 0, 30, "cooldownDecimalSeconds", 3)
    AddTooltip(customDecimal, "Cooldown text format",
        "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole "
            .. "seconds only.")
    GateControls(ctx, function() return item.placed.showCooldown ~= false end, {
        CdNumber("Cooldown size", 1, -76, 6, 40, "cooldownSize", 14),
        BindDropdown(ctx, cooldown, "Cooldown anchor", cdX(3), -76, Model.AuraAnchorValues(), cdCol,
            function() return item.placed.cooldownAnchor or "CENTER" end,
            { write = { container = C, source = function() return item end,
                fallback = "CENTER", after = function() Apply("AURAS3_CUSTOM_COOLDOWN_ANCHOR") end
            } --[[schema setter: J5.CustomStyle.21]] },
            AuraControlMeta(ctx, "custom-container.appearance.cooldown-anchor")),
        customDecimal,
        CdNumber("Cooldown X", 1, -130, -40, 40, "cooldownX", 0),
        CdNumber("Cooldown Y", 2, -130, -40, 40, "cooldownY", 0),
    })
    GateControls(ctx, function() return item.placed.showCooldownSwipe ~= false end, {
        BindDropdown(ctx, cooldown, "Swipe", cdX(2), -76, COOLDOWN_SWIPE_DIRECTION_VALUES, cdCol,
            function() return item.placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL" end,
            { write = { container = C, source = function() return item end,
                convert = function(value) return value == "REVERSE" end, after = function() Apply("AURAS3_CUSTOM_SWIPE_DIRECTION") end
            } --[[schema setter: J5.CustomStyle.22]] },
            AuraControlMeta(ctx, "custom-container.appearance.swipe-direction")),
    })
    return cooldown
end
--- Style > Duration Bar: the switch, its details and the state painter that
--- keeps them unavailable while the container shows fixed reminder slots.
--- Returns that painter.
local function BuildCustomStyleDurationBar(C)
    local ctx, b, index, Apply = C.ctx, C.b, C.index, C.Apply
    local item = C.styleItem
    local durationBar = AurasPage.Section(b, CustomStyleSectionId(index, "duration_bar"), "Duration Bar", 156, false)
    local barCol, barX, BarNumber = StyleGrid(C, durationBar)
    local durationBarControls, durationBarSwitch
    local durationBarNote = W.Text(durationBar, "", 24, -116, (durationBar._msuf2Width or b.width or 720) - 48, T.colors.muted)
    local function RefreshCustomDurationBarState()
        local placed = item.placed
        -- Fixed aura slots and Oil placeholders can show cooldown text/swipe,
        -- but neither owns the AuraButton duration-bar surface this group drives.
        local reminder = REMINDERS_AVAILABLE and placed.reminderEnabled == true
        local enabled = placed.showDurationBar == true and not reminder
        if durationBarSwitch then W.SetControlEnabled(durationBarSwitch, not reminder) end
        if durationBarControls then W.SetControlsEnabled(durationBarControls, enabled) end
        durationBarNote:SetText(reminder
            and "Reminder slots do not draw a duration bar." or "")
        if W.SetCollapsibleBadges then
            W.SetCollapsibleBadges(durationBar, {{
                text = reminder and Tr("Unavailable")
                    or (enabled and (M.Format("%d px / %s / %s", Round(tonumber(placed.durationBarHeight) or 2),
                        ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, placed.durationBarDisplay or "BAR_ONLY", "Bar Only"),
                        ChoiceLabel(DURATION_BAR_POSITION_VALUES, placed.durationBarPosition or "BOTTOM", "Bottom"))) or "Off"),
                kind = enabled and "accent" or "muted", showWhenClosed = true,
            }})
        end
    end
    -- A bar choice writes its placed key, applies and repaints the state.
    local function BarChoice(label, col, values, key, fallback, reason, path)
        return BindDropdown(ctx, durationBar, label, barX(col), -76, values, barCol,
            function() return item.placed[key] or fallback end,
            { write = { container = C, source = function() return item end, fallback = fallback,
                after = function() Apply(reason) RefreshCustomDurationBarState() end
            } --[[schema setter: J5.CustomStyle.DurationChoice]] },
            AuraControlMeta(ctx, path))
    end
    M.TrackRefresh(ctx, RefreshCustomDurationBarState)
    durationBarSwitch = BindSwitch(ctx, durationBar, "Duration bar", barX(1), -42, barCol, function() return item.placed.showDurationBar == true end,
        { write = { container = C, source = function() return item end, strictBoolean = true,
            after = function() Apply("AURAS3_CUSTOM_DURATION_BAR") RefreshCustomDurationBarState() end
        } --[[schema setter: J5.CustomStyle.DurationEnabled]] },
        AuraControlMeta(ctx, "custom-container.appearance.duration-bar"))
    durationBarControls = {
        BarNumber("Bar height", 1, -76, 1, 16, "durationBarHeight", 2, RefreshCustomDurationBarState),
        BarChoice("Bar display", 2, DURATION_BAR_DISPLAY_VALUES, "durationBarDisplay", "BAR_ONLY",
            "AURAS3_CUSTOM_DURATION_DISPLAY", "custom-container.appearance.duration-display"),
        BarChoice("Bar position", 3, DURATION_BAR_POSITION_VALUES, "durationBarPosition", "BOTTOM",
            "AURAS3_CUSTOM_DURATION_POSITION", "custom-container.appearance.duration-position"),
        BarChoice("Bar fill", 4, DURATION_BAR_DIRECTION_VALUES, "durationBarDirection", "REMAINING",
            "AURAS3_CUSTOM_DURATION_DIRECTION", "custom-container.appearance.duration-direction"),
    }
    return RefreshCustomDurationBarState
end
--- The closed-accordion badges of the Style sections.
local function TrackCustomStyleBadges(C, harmfulContainer, frameBasics, stack, cooldown, RefreshCustomDurationBarState)
    if not W.SetCollapsibleBadges then return end
    local item = C.styleItem
    local ToggleBadge = W.ToggleBadge
    M.TrackRefresh(C.ctx, function()
        local placed = item.placed
        local zoom = Round(tonumber(placed.iconZoom) or 100)
        local opacity = floor(((tonumber(placed.alpha) or 1) * 100) + 0.5)
        local frameBasicsBadges = {
            { text = M.Format("Zoom %d%%", zoom), kind = "info", showWhenClosed = true },
            ToggleBadge("Tooltip", placed.showTooltip ~= false),
        }
        if opacity < 100 then
            frameBasicsBadges[#frameBasicsBadges + 1] = { text = M.Format("Opacity %d%%", opacity), kind = "info", showWhenClosed = true }
        end
        if harmfulContainer then
            local borderMode = tostring(placed.debuffTypeBorderMode or "OFF"):upper()
            frameBasicsBadges[#frameBasicsBadges + 1] = {
                text = M.Format("Border %s", ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode)),
                kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
            }
        end
        W.SetCollapsibleBadges(frameBasics, frameBasicsBadges)

        local stackEnabled = placed.showStacks ~= false
        W.SetCollapsibleBadges(stack, {{
            text = stackEnabled and (M.Format("%d px / %s", Round(tonumber(placed.stackSize) or 14),
                AnchorLabel(placed.stackAnchor or "BOTTOMRIGHT"))) or "Off",
            kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
        }})

        local cooldownEnabled = placed.showCooldown ~= false
        local decimal = Round(tonumber(placed.cooldownDecimalSeconds) or 3)
        W.SetCollapsibleBadges(cooldown, {
            { text = cooldownEnabled and (M.Format("%d px / %s / %s", Round(tonumber(placed.cooldownSize) or 14),
                AnchorLabel(placed.cooldownAnchor or "CENTER"),
                ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL", "Normal"))) or "Off",
                kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
            { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
        })

        RefreshCustomDurationBarState()
    end)
end

local function BuildCustomAppearanceTool(C)
    if C.tool == "appearance" then
        -- Every Custom container, including Player Defensives and Dots on
        -- Target, binds visual controls to this UnitFrame-owned record.
        local harmfulContainer = C.isTargetDots or tostring(C.styleItem.auraType or "BUFF"):upper() == "DEBUFF"
        local frameBasics = BuildCustomStyleBasics(C, harmfulContainer)
        BuildCustomAppearancePandemic(C)
        local stack = BuildCustomStyleStack(C)
        local cooldown = BuildCustomStyleCooldown(C)
        local RefreshCustomDurationBarState = BuildCustomStyleDurationBar(C)
        TrackCustomStyleBadges(C, harmfulContainer, frameBasics, stack, cooldown, RefreshCustomDurationBarState)
        return true
    end
end

local function BuildCustomEffectTool(C)
    local ctx, b, index, tool, isTargetDots, styleItem, Apply, Grid = C.ctx, C.b, C.index, C.tool, C.isTargetDots, C.styleItem, C.Apply, C.Grid
    if tool == "effect" then
        local item = styleItem
        local section = AurasPage.Section(b, CustomStyleSectionId(index, "full_frame"), "Full-Frame Effect", 210, false)
        local w = section._msuf2Width or b.width or 720
        local col3, gap = Grid(w, 3)
        BindDropdown(ctx, section, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, w - 48,
            function() return item.frame.type or "none" end,
            { write = { container = C, source = function() return item end,
                fallback = "none", after = function() Apply("AURAS3_CUSTOM_EFFECT") end
            } --[[schema setter: J5.CustomStyle.23]] },
            AuraControlMeta(ctx, "custom-container.effect.type"))
        local color = W.Color(section, "Color")
        AurasPage.BindColor(ctx, color,
            function()
                local c = item.frame.color
                return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88
            end,
            function(r, g, blue)
                local a = item.frame.color[4] or 0.8
                item.frame.color = { r, g, blue, a }
                Apply("AURAS3_CUSTOM_EFFECT_COLOR")
            end,
            AuraControlMeta(ctx, "custom-container.effect.color"))
        HideInlineSwatch(color)
        BindSlider(ctx, section, "Opacity", 24, -96, 5, 100, 5, col3,
            function() return floor(((item.frame.color[4] or 0.8) * 100) + 0.5) end,
            function(value)
                item.frame.color[4] = (tonumber(value) or 80) / 100
                item.frame.tintAlpha = item.frame.color[4]
                Apply("AURAS3_CUSTOM_EFFECT_ALPHA")
            end,
            AuraControlMeta(ctx, "custom-container.effect.opacity"))
        BindSlider(ctx, section, "Layer (0-30)", 24 + col3 + gap, -96, 0, 30, 1, col3,
            function() return tonumber(item.frame.layer) or 0 end,
            { write = { container = C, source = function() return item end,
                convert = function(value) return floor(tonumber(value) or 0) end, after = function() Apply("AURAS3_CUSTOM_EFFECT_LAYER") end
            } --[[schema setter: J5.CustomStyle.24]] },
            AuraControlMeta(ctx, "custom-container.effect.layer"))
        BindSlider(ctx, section, "Thickness", 24 + 2 * (col3 + gap), -96, 1, 16, 1, col3,
            function() return tonumber(item.frame.thickness) or 2 end,
            { write = { container = C, source = function() return item end,
                numberDefault = 2, after = function() Apply("AURAS3_CUSTOM_EFFECT_THICKNESS") end
            } --[[schema setter: J5.CustomStyle.25]] },
            AuraControlMeta(ctx, "custom-container.effect.thickness"))
        BindSlider(ctx, section, "Priority", 24, -150, 1, 10, 1, col3,
            function() return tonumber(item.frame.priority) or 5 end,
            { write = { container = C, source = function() return item end,
                numberDefault = 5, after = function() Apply("AURAS3_CUSTOM_EFFECT_PRIORITY") end
            } --[[schema setter: J5.CustomStyle.26]] },
            AuraControlMeta(ctx, "custom-container.effect.priority"))
        -- Same capability test as Pandemic Warning & Style: without the native
        -- Pandemic applier (every Classic backend) nothing can honour this switch.
        if isTargetDots and PandemicVisualSupported() then
            local pandemicOnly = BindSwitch(ctx, section, "Only during Pandemic window", 24 + col3 + gap, -150,
                col3 * 2 + gap, function() return item.frame.onlyInPandemicWindow == true end,
                { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_TARGET_DOT_EFFECT_PANDEMIC_ONLY", true) end
            } --[[schema setter: J5.CustomStyle.27]] },
                AuraControlMeta(ctx, "custom-container.effect.only-during-pandemic-window"))
            AddTooltip(pandemicOnly, "Pandemic-only Full-Frame effect",
                "Shows this effect only while a tracked DoT is in its native Pandemic window. Multiple DoTs in Pandemic can intensify the same effect. On "
                    .. "12.1.0 Blizzard runs an OnUpdate on each visible aura button while its Pandemic timing is available; 12.1.5 and WoW Forever use a "
                    .. "native timer instead.")
        end
        if W.SetCollapsibleBadges then
            M.TrackRefresh(ctx, function()
                local effectType = tostring(item.frame.type or "none")
                local badges = {{
                    text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                    kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
                }}
                if isTargetDots and PandemicVisualSupported() and item.frame.onlyInPandemicWindow == true then
                    badges[#badges + 1] = { text = "Pandemic only", kind = "info", showWhenClosed = true }
                end
                W.SetCollapsibleBadges(section, badges)
            end)
        end
        return true
    end
end

local function BuildCustomBehaviorTool(C)
    local ctx, b, unit, index, tool, customActionPath, isPlayerDefensives, isTargetDots, item, Apply =
        C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.isPlayerDefensives, C.isTargetDots, C.item, C.Apply
    if tool == "behavior" then
        local sortLane = (isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF") and "debuff" or "buff"
        local supportsCustomPriority = not isPlayerDefensives
        local section = b:Section("Ordering", 190)
        local w = section._msuf2Width or b.width or 720
        -- Keep every custom container's identity separate. Exact-ID custom
        -- containers can each persist their own CUSTOM_PRIORITY or ordinary
        -- sort mode without sharing a lane preset.
        local orderingPath = customActionPath .. ".ordering"
        local visibleOrderingPath = isTargetDots and "custom-container.dots-on-target.ordering"
            or (isPlayerDefensives and "custom-container.defensive-buffs.ordering" or orderingPath)
        local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(sortLane, supportsCustomPriority), w - 48,
            function() return NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod, supportsCustomPriority) end,
            function(value)
                if supportsCustomPriority and value == "CUSTOM_PRIORITY"
                    and Model.EnableCustomContainerSpellPriority then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                else
                    item.placed.sortMethod = value or "DEFAULT"
                end
                Apply("AURAS3_CUSTOM_SORT_METHOD", supportsCustomPriority)
            end,
            AuraControlMetaAtVisiblePath(ctx,
                orderingPath .. "." .. sortLane .. "-sort-method",
                visibleOrderingPath .. "." .. sortLane .. "-sort-method"))
        AddTooltip(sortMethod, "Aura sorting", supportsCustomPriority
            and "Custom Priority packs active tracked auras into the configured order. Inactive entries leave no gap; drag the spell rows in Setup to change "
                .. "their priority."
            or "Only relevant sorting methods are shown for buffs and debuffs.")
        local sortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, w - 48,
            function() return item.placed.sortReverse == true and "REVERSE" or "NORMAL" end,
            { write = { container = C, source = function() return item end,
                convert = function(value) return value == "REVERSE" end, after = function() Apply("AURAS3_CUSTOM_SORT_DIRECTION") end
            } --[[schema setter: J5.CustomStyle.28]] },
            AuraControlMetaAtVisiblePath(ctx,
                orderingPath .. ".sort-direction",
                visibleOrderingPath .. ".sort-direction"))
        AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
        -- Fixed reminder slots take their order from the Whitelist, so nothing
        -- on this tab can influence them. Leaving the controls live would let
        -- the page promise something the runtime ignores.
        local orderingNote = W.Text(section, "", 24, -156, w - 48, T.colors.muted)
        M.TrackRefresh(ctx, function()
            local reminder = REMINDERS_AVAILABLE and item.placed.reminderEnabled == true
            if W.SetControlsEnabled then
                W.SetControlsEnabled({ sortMethod }, not reminder)
                W.SetControlsEnabled({ sortDirection }, not reminder
                    and (not supportsCustomPriority
                        or NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod, supportsCustomPriority) ~= "CUSTOM_PRIORITY"))
            end
            orderingNote:SetText(reminder
                and "Sorting is off while this container shows fixed reminder slots \194\183 their order comes from the Whitelist."
                or "")
        end)
        return true
    end
end

Parts.BuildCustomFiltersTool = BuildCustomFiltersTool

Parts.BuildCustomLayoutTool = BuildCustomLayoutTool

Parts.BuildCustomAppearanceTool = BuildCustomAppearanceTool

Parts.BuildCustomEffectTool = BuildCustomEffectTool

Parts.BuildCustomBehaviorTool = BuildCustomBehaviorTool
