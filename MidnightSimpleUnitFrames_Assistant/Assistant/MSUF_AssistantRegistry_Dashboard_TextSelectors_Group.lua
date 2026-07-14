-- Assistant Dashboard group text selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard_TextSelectors.lua; unit text selectors stay in the main text selector module.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

function A.DashboardRegistry.BuildGroupTextSelectors(ctx)
    if type(ctx) ~= "table" then return {} end

    local Menu = ctx.M or M
    local ResolveGroupScope = ctx.ResolveGroupScope
    local PersistScalar = ctx.PersistScalar
    local PersistTableValue = ctx.PersistTableValue
    local PersistNestedTableValue = ctx.PersistNestedTableValue
    local OpenMenuPage = ctx.OpenMenuPage
    local SelectorBool = ctx.SelectorBool
    local GroupLabel = ctx.GroupLabel
    local ResolveTextTab = ctx.ResolveTextTab
    local ResolveTextSlot = ctx.ResolveTextSlot
    local RememberSelectedTextTarget = ctx.RememberSelectedTextTarget
    local TEXT_TAB_LABELS = ctx.TEXT_TAB_LABELS or {}
    local TEXT_SLOT_LABELS = ctx.TEXT_SLOT_LABELS or {}

    if type(Menu) ~= "table" then return {} end
    if type(ResolveGroupScope) ~= "function" then return {} end
    if type(PersistScalar) ~= "function" or type(PersistTableValue) ~= "function" or type(PersistNestedTableValue) ~= "function" then return {} end
    if type(OpenMenuPage) ~= "function" or type(SelectorBool) ~= "function" then return {} end
    if type(GroupLabel) ~= "function" or type(ResolveTextTab) ~= "function" then return {} end
    if type(ResolveTextSlot) ~= "function" or type(RememberSelectedTextTarget) ~= "function" then return {} end

    local function FocusGroupText(scope, tab, slot)
        if Menu and type(Menu.FocusGFPreviewTextSlot) == "function" then
            Menu.FocusGFPreviewTextSlot(tab, slot, true)
        end
        if type(_G.MSUF_EM2_SetFocusSelection) == "function" then
            local key = scope == "raid" and "gf_raid" or (scope == "mythicraid" and "gf_mythicraid" or "gf_party")
            _G.MSUF_EM2_SetFocusSelection(key, tab, slot, { source = "assistant", clearHover = true })
        end
    end

    local function CurrentGroupTextSlot(scope, tab)
        local byScope = Menu and Menu.gfTextSlotSelection and Menu.gfTextSlotSelection[scope]
        local slot = byScope and byScope[tab]
        return ResolveTextSlot(slot) or "center"
    end

    local function SetGroupTextSelector(args)
        local scope = ResolveGroupScope(args and args.scope) or "party"
        local tab = ResolveTextTab(args and args.tab)
        local slot = ResolveTextSlot(args and args.slot)
        if not tab then return false, "Which group text tab do you want me to select?" end
        PersistScalar("gfScope", scope)
        PersistTableValue("gfTextTabSelection", scope, tab)
        if slot and (tab == "hp" or tab == "power") then PersistNestedTableValue("gfTextSlotSelection", scope, tab, slot) end
        RememberSelectedTextTarget("group", scope, tab, slot)
        FocusGroupText(scope, tab, slot)
        OpenMenuPage("gf_layout")
        return true, "Selected " .. GroupLabel(scope) .. " " .. TEXT_TAB_LABELS[tab] .. (slot and (" " .. TEXT_SLOT_LABELS[slot] .. " slot") or " tab") .. "."
    end

    local function SetGroupTextMoveTogether(args)
        local scope = ResolveGroupScope(args and args.scope) or "party"
        local tab = ResolveTextTab(args and args.tab)
        local value = SelectorBool(args and args.value)
        if tab ~= "hp" and tab ~= "power" then return false, "HP and Power text are the move-together choices here." end
        PersistScalar("gfScope", scope)
        Menu.gfTextMoveTogether = type(Menu.gfTextMoveTogether) == "table" and Menu.gfTextMoveTogether or {}
        Menu.gfTextMoveTogether[scope] = type(Menu.gfTextMoveTogether[scope]) == "table" and Menu.gfTextMoveTogether[scope] or {}
        Menu.gfTextMoveTogether[scope][tab] = value
        PersistTableValue("gfTextTabSelection", scope, tab)
        local slot = value and nil or CurrentGroupTextSlot(scope, tab)
        RememberSelectedTextTarget("group", scope, tab, slot)
        FocusGroupText(scope, tab, slot)
        if Menu and type(Menu.RefreshGFNativePreviews) == "function" then Menu.RefreshGFNativePreviews() end
        OpenMenuPage("gf_layout")
        return true, "Set " .. GroupLabel(scope) .. " " .. TEXT_TAB_LABELS[tab] .. " move text as one group " .. (value and "on" or "off") .. "."
    end

    return {
        SetGroupTextSelector = SetGroupTextSelector,
        SetGroupTextMoveTogether = SetGroupTextMoveTogether,
    }
end
