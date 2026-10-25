local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua"
-- Core functions this page calls by their global names: required here at
-- load and resolved once below: their callers run on every setting change.
M.RequireGlobals(FILE, {
    "MSUF_SuppressBlizzardPlayerCastbars",
    "MSUF_ShowReloadRecommendedPopup",
})
local function Core(name)
    return MSUF.Require(name, "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua")
end

-- Menu2 Unit visual sections.
-- Builds controls for portrait, castbar detail, detached power, border/shape, and related
-- frame visuals. It writes through UnitPage helpers and delegates live refresh to runtimes.
local W = M.Widgets or {}
local Schema = M.ControlSchema
-- Unit rows retain the existing typed binding owners, including their refusal,
-- history and normalization policies. Accessors resolve the live profile on input.
local ROW_OPTIONS = Schema.UnitOptions()
local function ControlRow(ctx, parent, row)
    return Schema.Build(ctx, parent, { row }, ROW_OPTIONS)[row[2]]
end
-- Card rows share their id scheme and layout domain; notes are wrapped description text.
local function SectionCard(ctx, unit, parent, area, name, args)
    return ControlRow(ctx, parent, { "card", "menu2.uf_" .. unit .. "." .. area .. "." .. name, nil, args, scope = unit, domain = "layout" })
end
local function SectionNote(ctx, unit, parent, name, text, x, y, width, wrap)
    local note = ControlRow(ctx, parent, { "text", "menu2.uf_" .. unit .. ".unit.visuals." .. name .. ".description", nil,
        { text, x, y, width }, scope = unit, domain = "description" })
    if wrap and note.SetWordWrap then note:SetWordWrap(true) end
    return note
end
local PixelLayoutRegion = Core("MSUF_PixelLayoutRegion")
local EnsureCooldownWidthObservers = Core("MSUF_EnsureCooldownWidthObservers")
local CastbarsOnSettingsChanged = Core("MSUF_Castbars_OnSettingsChanged")
local SuppressBlizzardPlayerCastbars = Core("MSUF_SuppressBlizzardPlayerCastbars")
local ShowReloadRecommendedPopup = Core("MSUF_ShowReloadRecommendedPopup")
local UP = M.UnitPage or {}
local floor = math.floor
local max = math.max
local POWER_UNITS, CASTBAR_FIELDS, PORTRAIT_RENDER = UP.POWER_UNITS or {}, UP.CASTBAR_FIELDS or {}, UP.PORTRAIT_RENDER or {}
local PORTRAIT_SHAPES, PORTRAIT_BORDERS = UP.PORTRAIT_SHAPES or {}, UP.PORTRAIT_BORDERS or {}
local GetConf, GetGeneral, GetBars, UnitTopLabel, ReadBool = UP.GetConf, UP.GetGeneral, UP.GetBars, UP.UnitTopLabel, UP.ReadBool
local SetBool, ReadNumber, SetNumber, ReadGeneralBool, SetGeneralBool = UP.SetBool, UP.ReadNumber, UP.SetNumber, UP.ReadGeneralBool, UP.SetGeneralBool
local NormalizePortrait, SetPortraitValue = UP.NormalizePortrait, UP.SetPortraitValue
local IsPlayerPowerManagedByClassResources, ControlMeta, SettingMeta = UP.IsPlayerPowerManagedByClassResources, UP.ControlMeta, UP.SettingMeta
local ReviewedMeta, RegisterControl = UP.ReviewedMeta, UP.RegisterControl
local CASTBAR_UNITS = M.KeySetFromWords "player target focus boss arena"
local UnitSectionShared = M.UnitSectionsShared or {}
-- Tab workspaces shared by the Portrait and Castbar sections. A selection lives in
-- M[stateKey][unit]; a tab key is valid when the section's height table lists it,
-- anything else reads as General.
local function NormalizeTabKey(heights, key)
    return heights[key] and key or "general"
end
local function CurrentTab(stateKey, heights, unit)
    if unit == nil then return "general" end
    M[stateKey] = M[stateKey] or {}
    local key = NormalizeTabKey(heights, M[stateKey][unit])
    M[stateKey][unit] = key
    return key
end
-- Resizes a collapsible section's body to the selected tab's height and relays the page out when it changed.
local function SetSectionBodyHeight(sec, height, fallback)
    height = max(120, floor((tonumber(height) or fallback) + 0.5))
    local entry = sec and sec._msuf2CollapsibleEntry
    if sec and sec.SetHeight then sec:SetHeight(height) end
    if entry then
        local changed = entry.contentHeight ~= height
        entry.contentHeight = height
        if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
        if entry.outer and entry.outer.SetHeight then entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and height or 0)) end
        if changed and entry.builder and entry.builder.RelayoutCollapsibles then entry.builder:RelayoutCollapsibles() end
    end
end
-- The tab bar of a section workspace: owns tab selection, the guided-select hook search routes
-- use, and the control record. spec = { stateKey, heights, values, width, frames, controlId, label, afterRefresh }.
local function BuildSectionTabs(ctx, sec, unit, spec)
    local stateKey, heights = spec.stateKey, spec.heights
    local tabs, RefreshTabs, ReadTab, SetGuidedTab = W.SegmentTabs(ctx, sec, {
        label = "", values = spec.values, width = spec.width, frames = spec.frames, defaultTab = "general",
        get = function() return CurrentTab(stateKey, heights, unit) end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
            M[stateKey] = M[stateKey] or {}
            M[stateKey][unit] = NormalizeTabKey(heights, v)
        end,
        afterRefresh = spec.afterRefresh,
        x = 20, y = -12,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    RegisterControl(tabs, ctx, spec.controlId, spec.label, "segment", "ephemeral")
    Schema.Owned(tabs, unit, "sectionNavigation")
    sec._msuf2GuidedSelectTab = function(tab)
        tab = NormalizeTabKey(heights, tab)
        if type(ReadTab) == "function" and ReadTab() == tab then return true end
        if type(SetGuidedTab) == "function" then
            SetGuidedTab(tab)
        else
            M[stateKey] = M[stateKey] or {}
            M[stateKey][unit] = tab
            if type(RefreshTabs) == "function" then RefreshTabs() end
        end
        return type(ReadTab) ~= "function" or ReadTab() == tab
    end
end
-- A control that lives on one tab: an exact search link selects that tab before the control is focused.
local function PrepareTabTarget(sec, kind, widget, tab, settingKey)
    if not widget then return end
    widget._msuf2ExactTargetKinds = { [kind] = true }
    widget._msuf2ExactTargetContracts = {
        [kind] = { [tab] = tostring(settingKey or "") },
    }
    widget._msuf2PrepareExactSearchTarget = function(_, exactTarget)
        if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= kind
            or tostring(exactTarget.prepareValue or "") ~= tab
        then
            return false
        end
        return sec._msuf2GuidedSelectTab and sec._msuf2GuidedSelectTab(tab) == true
    end
end


-- Build independent section owners once; callbacks retain direct function bindings.
local BuildPortrait, PreparePortraitSwitch, PortraitLayoutForWidth, CurrentPortraitTab = M.UnitVisualFactories.Portrait(
    { GetConf = GetConf, ReadBool = ReadBool, ReadNumber = ReadNumber, SetNumber = SetNumber,
        NormalizePortrait = NormalizePortrait, SetPortraitValue = SetPortraitValue },
    { Widgets = W, Schema = Schema, Row = ControlRow, Card = SectionCard, PixelLayoutRegion = PixelLayoutRegion,
        ControlMeta = ControlMeta, ReviewedMeta = ReviewedMeta, Shared = UnitSectionShared },
    { Render = PORTRAIT_RENDER, Shapes = PORTRAIT_SHAPES, Borders = PORTRAIT_BORDERS, CastbarUnits = CASTBAR_UNITS },
    { Normalize = NormalizeTabKey, Current = CurrentTab, SetBodyHeight = SetSectionBodyHeight,
        Build = BuildSectionTabs, PrepareTarget = PrepareTabTarget }
)
local BuildPower, PreparePowerSwitch, PowerSectionHeight = M.UnitVisualFactories.Power(
    { Units = POWER_UNITS, GetConf = GetConf, GetGeneral = GetGeneral, GetBars = GetBars, UnitTopLabel = UnitTopLabel,
        ReadBool = ReadBool, SetBool = SetBool, ReadNumber = ReadNumber, SetNumber = SetNumber,
        IsPlayerPowerManagedByClassResources = IsPlayerPowerManagedByClassResources },
    { Widgets = W, Schema = Schema, Row = ControlRow, Card = SectionCard, SettingMeta = SettingMeta,
        RegisterControl = RegisterControl, Shared = UnitSectionShared },
    { Core = Core, EnsureCooldownWidthObservers = EnsureCooldownWidthObservers }
)
local BuildCastbar, PrepareCastbarSwitch, CastbarTabHeight, CurrentCastbarTab = M.UnitVisualFactories.Castbar(
    { Fields = CASTBAR_FIELDS, GetGeneral = GetGeneral, UnitTopLabel = UnitTopLabel, ReadBool = ReadBool, SetBool = SetBool,
        ReadGeneralBool = ReadGeneralBool, SetGeneralBool = SetGeneralBool, NormalizePortrait = NormalizePortrait,
        SetPortraitValue = SetPortraitValue },
    { Widgets = W, Schema = Schema, Row = ControlRow, Card = SectionCard, Note = SectionNote, SettingMeta = SettingMeta,
        ReviewedMeta = ReviewedMeta, RegisterControl = RegisterControl, Shared = UnitSectionShared },
    { OnSettingsChanged = CastbarsOnSettingsChanged, SuppressBlizzardPlayerCastbars = SuppressBlizzardPlayerCastbars,
        ShowReloadPopup = ShowReloadRecommendedPopup },
    { Normalize = NormalizeTabKey, Current = CurrentTab, SetBodyHeight = SetSectionBodyHeight,
        Build = BuildSectionTabs, PrepareTarget = PrepareTabTarget }
)

if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({ id = "portrait", title = "Portrait", height = function(ctx, _, unit) return PortraitLayoutForWidth(ctx and ctx.width,
        CurrentPortraitTab(unit)).height end, placement = "after_inline_text", order = 10, build = BuildPortrait,
        prepareShell = function(ctx, sec, unit) PreparePortraitSwitch(ctx, sec, unit) end })
    UP.RegisterSection({ id = "power", sectionId = "power_bar", title = "Power Bar", height = function(_, _, unit) return PowerSectionHeight(unit) end,
        placement = "after_inline_text", order = 20, units = POWER_UNITS, build = BuildPower, prepareShell = PreparePowerSwitch })
    UP.RegisterSection({ id = "castbar", title = "Castbar", height = function(_, _, unit) return CastbarTabHeight(unit, CurrentCastbarTab(unit)) end,
        placement = "after_inline_text", order = 30, units = CASTBAR_UNITS, build = BuildCastbar, prepareShell = PrepareCastbarSwitch })
end
