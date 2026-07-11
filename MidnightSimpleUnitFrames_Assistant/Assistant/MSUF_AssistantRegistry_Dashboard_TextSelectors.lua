-- Assistant Dashboard text selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; the main dashboard registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}
local BuildGroupTextSelectors = A.DashboardRegistry.BuildGroupTextSelectors

local TEXT_TAB_LABELS = {
    name = "Name Text",
    hp = "HP Text",
    power = "Power Text",
    advanced = "Advanced Text",
}

local TEXT_SLOT_LABELS = {
    left = "left",
    center = "center",
    right = "right",
}

function A.DashboardRegistry.BuildTextSelectors(ctx)
    if type(ctx) ~= "table" then return {} end

    local Menu = ctx.M or M
    local Assistant = ctx.A or A
    local NormalizeKey = ctx.NormalizeKey
    local ResolveUnitKey = ctx.ResolveUnitKey
    local ResolveGroupScope = ctx.ResolveGroupScope
    local PersistScalar = ctx.PersistScalar
    local PersistTableValue = ctx.PersistTableValue
    local PersistNestedTableValue = ctx.PersistNestedTableValue
    local OpenMenuPage = ctx.OpenMenuPage
    local SelectorBool = ctx.SelectorBool
    local UnitLabel = ctx.UnitLabel
    local GroupLabel = ctx.GroupLabel
    local UNIT_PAGE_KEYS = ctx.UNIT_PAGE_KEYS or {}

    if type(Menu) ~= "table" then return {} end
    if type(NormalizeKey) ~= "function" then return {} end
    if type(ResolveUnitKey) ~= "function" or type(ResolveGroupScope) ~= "function" then return {} end
    if type(PersistScalar) ~= "function" or type(PersistTableValue) ~= "function" or type(PersistNestedTableValue) ~= "function" then return {} end
    if type(OpenMenuPage) ~= "function" or type(SelectorBool) ~= "function" then return {} end
    if type(UnitLabel) ~= "function" or type(GroupLabel) ~= "function" then return {} end
    if type(BuildGroupTextSelectors) ~= "function" then return {} end

    local function ResolveTextTab(tab)
        tab = NormalizeKey(tab)
        if tab == "health" or tab == "healthtext" then tab = "hp" end
        if tab == "mana" or tab == "manatext" or tab == "powertext" then tab = "power" end
        if tab == "nametext" then tab = "name" end
        if TEXT_TAB_LABELS[tab] then return tab end
        return nil
    end

    local function ResolveTextSlot(slot)
        slot = NormalizeKey(slot)
        if slot == "centre" or slot == "middle" then slot = "center" end
        if TEXT_SLOT_LABELS[slot] then return slot end
        return nil
    end

    local function FocusUnitText(unit, tab, slot)
        if type(_G.MSUF_UFPreview_FocusTextSlot) == "function" then
            _G.MSUF_UFPreview_FocusTextSlot(unit, tab, slot, true)
        end
        if type(_G.MSUF_EM2_SetFocusSelection) == "function" then
            _G.MSUF_EM2_SetFocusSelection(unit, tab, slot, { source = "assistant", clearHover = true })
        end
    end

    local function CurrentUnitTextSlot(unit, tab)
        local byUnit = Menu and Menu.unitTextSlotSelection and Menu.unitTextSlotSelection[unit]
        local slot = byUnit and byUnit[tab]
        return ResolveTextSlot(slot) or "center"
    end

    local function RememberSelectedTextTarget(frameType, unitOrScope, tab, slot)
        if tab ~= "hp" and tab ~= "power" then return end
        slot = ResolveTextSlot(slot)
        if not slot then return end
        local ctxState = Assistant.GetContext and Assistant.GetContext()
        if not ctxState then return end
        ctxState.lastTextFrameType = frameType
        ctxState.lastTextUnit = unitOrScope
        ctxState.lastTextArea = tab
        ctxState.lastTextSlot = slot
        ctxState.selectedTextEditorTarget = {
            frameType = frameType,
            unit = unitOrScope,
            tab = tab,
            slot = slot,
        }
    end

    local function SetUnitTextSelector(args)
        local unit = ResolveUnitKey(args and args.unit)
        local tab = ResolveTextTab(args and args.tab)
        local slot = ResolveTextSlot(args and args.slot)
        if not unit then return false, "Which unit text menu do you want me to select?" end
        if not tab then return false, "Which text tab do you want me to select?" end
        PersistTableValue("unitTextTabSelection", unit, tab)
        if slot and (tab == "hp" or tab == "power") then PersistNestedTableValue("unitTextSlotSelection", unit, tab, slot) end
        RememberSelectedTextTarget("unitframe", unit, tab, slot)
        FocusUnitText(unit, tab, slot)
        OpenMenuPage(UNIT_PAGE_KEYS[unit])
        return true, "Selected " .. UnitLabel(unit) .. " " .. TEXT_TAB_LABELS[tab] .. (slot and (" " .. TEXT_SLOT_LABELS[slot] .. " slot") or " tab") .. "."
    end

    local function SetUnitTextMoveTogether(args)
        local unit = ResolveUnitKey(args and args.unit)
        local tab = ResolveTextTab(args and args.tab)
        local value = SelectorBool(args and args.value)
        if not unit then return false, "Which unit text move mode do you want me to set?" end
        if tab ~= "hp" and tab ~= "power" then return false, "HP and Power text are the move-together choices here." end
        Menu.unitTextMoveTogether = type(Menu.unitTextMoveTogether) == "table" and Menu.unitTextMoveTogether or {}
        Menu.unitTextMoveTogether[unit] = type(Menu.unitTextMoveTogether[unit]) == "table" and Menu.unitTextMoveTogether[unit] or {}
        Menu.unitTextMoveTogether[unit][tab] = value
        PersistTableValue("unitTextTabSelection", unit, tab)
        local slot = value and nil or CurrentUnitTextSlot(unit, tab)
        RememberSelectedTextTarget("unitframe", unit, tab, slot)
        FocusUnitText(unit, tab, slot)
        if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh("MSUF_ASSISTANT_TEXT_MOVE_MODE") end
        OpenMenuPage(UNIT_PAGE_KEYS[unit])
        return true, "Set " .. UnitLabel(unit) .. " " .. TEXT_TAB_LABELS[tab] .. " move text as one group " .. (value and "on" or "off") .. "."
    end

    local GroupTextSelectors = BuildGroupTextSelectors({
        M = Menu,
        ResolveGroupScope = ResolveGroupScope,
        PersistScalar = PersistScalar,
        PersistTableValue = PersistTableValue,
        PersistNestedTableValue = PersistNestedTableValue,
        OpenMenuPage = OpenMenuPage,
        SelectorBool = SelectorBool,
        GroupLabel = GroupLabel,
        ResolveTextTab = ResolveTextTab,
        ResolveTextSlot = ResolveTextSlot,
        RememberSelectedTextTarget = RememberSelectedTextTarget,
        TEXT_TAB_LABELS = TEXT_TAB_LABELS,
        TEXT_SLOT_LABELS = TEXT_SLOT_LABELS,
    })

    return {
        SetUnitTextSelector = SetUnitTextSelector,
        SetUnitTextMoveTogether = SetUnitTextMoveTogether,
        SetGroupTextSelector = GroupTextSelectors.SetGroupTextSelector,
        SetGroupTextMoveTogether = GroupTextSelectors.SetGroupTextMoveTogether,
    }
end
