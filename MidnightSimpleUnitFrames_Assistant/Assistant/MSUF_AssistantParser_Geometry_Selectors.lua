-- Assistant geometry selector parser: handles selector-state and page-local geometry phrases.
-- It resolves UI intent only; applying DB changes remains in registry/action execution.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local ContainsAny = P.ContainsAny
local DetectBoolean = P.DetectBoolean
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local CurrentPageUnit = P.CurrentPageUnit
local ClassPowerColorTokenForText = P.ClassPowerColorTokenForText
local PowerColorTokenForText = P.PowerColorTokenForText
local GroupStatusIconForText = P.GroupStatusIconForText
local TextSelectorTab = P.TextSelectorTab
local TextSelectorSlot = P.TextSelectorSlot
local TextSelectorIntent = P.TextSelectorIntent
local Data = A.ParserData or {}
A.ParserData = Data
local GS = Data.GEOMETRY_SELECTOR_TERMS or {}

-- Menu selector parser for UI-only changes.
-- Selecting a visible tab/dropdown/slot should not mutate the underlying setting value; it
-- only changes the active editor selection so the user lands on the relevant control.
local MENU_SELECTOR_VERBS = GS.MENU_SELECTOR_VERBS or {}

local function HasMenuSelectorVerb(text)
    return ContainsAny(text, MENU_SELECTOR_VERBS)
end

local function MenuSelectorAction(args, label, summary)
    local action = Registry and Registry:GetAction("set_menu_selector_state")
    return action and {
        kind = "action",
        action = action,
        args = args,
        label = label or "Choose menu option",
        summary = summary or "Selects a visible menu tab, list choice, or editor slot without changing the actual option.",
    } or nil
end

local function SelectorUnit(text)
    local units = DetectUnits(text)
    return units[1] or CurrentPageUnit()
end

local function SelectorGroupScope(text)
    local groups = DetectGroups(text)
    if groups[1] then return groups[1] end
    if M and (M.gfScope == "party" or M.gfScope == "raid" or M.gfScope == "mythicraid") then return M.gfScope end
    return "party"
end

local function TextMoveTogetherIntent(text)
    if ContainsAny(text, GS.TEXT_MOVE_SEPARATE_TERMS)
        and ContainsAny(text, GS.TEXT_MOVE_TEXT_TERMS)
        and ContainsAny(text, GS.TEXT_MOVE_UNIT_TERMS)
    then
        return true
    end
    return ContainsAny(text, GS.TEXT_MOVE_INTENT_TERMS)
end

local function TextMoveTogetherValue(text)
    if ContainsAny(text, GS.TEXT_MOVE_SEPARATE_TERMS)
        and ContainsAny(text, GS.TEXT_MOVE_TEXT_TERMS)
        and ContainsAny(text, GS.TEXT_MOVE_UNIT_TERMS)
    then
        return false
    end
    if ContainsAny(text, GS.TEXT_MOVE_SEPARATE_SLOT_TERMS) then
        return false
    end
    local value = DetectBoolean(text)
    if value ~= nil then return value end
    return true
end

local function NaturalTextSelectorSlot(text)
    if not ContainsAny(text, GS.NATURAL_TEXT_SELECTOR_ACTION_TERMS) then return nil end
    if ContainsAny(text, GS.NATURAL_TEXT_SELECTOR_REJECT_TERMS) then
        return nil
    end
    local left = ContainsAny(text, GS.TEXT_LEFT_TERMS)
    local center = ContainsAny(text, GS.TEXT_CENTER_TERMS)
    local right = ContainsAny(text, GS.TEXT_RIGHT_TERMS)
    local count = (left and 1 or 0) + (center and 1 or 0) + (right and 1 or 0)
    if count ~= 1 then return nil end
    if left then return "left" end
    if center then return "center" end
    if right then return "right" end
    return nil
end

local function StatusSelectorTab(text)
    if ContainsAny(text, GS.STATUS_ADVANCED_TAB_TERMS) then return "advanced" end
    if ContainsAny(text, GS.STATUS_BASIC_TAB_TERMS) then return "basic" end
    return nil
end

local function StatusSelectorIntent(text)
    if ContainsAny(text, GS.STATUS_SELECTOR_INTENT_TERMS) then
        return true
    end
    return ContainsAny(text, GS.STATUS_SELECTOR_FALLBACK_TERMS)
end

function P.ClassPowerStyleTab(text)
    if ContainsAny(text, GS.CLASS_POWER_STYLE_RESOURCES_TERMS) then return "resources" end
    if ContainsAny(text, GS.CLASS_POWER_STYLE_TEXT_TERMS) then return "text" end
    if ContainsAny(text, GS.CLASS_POWER_STYLE_OPACITY_TERMS) then return "opacity" end
    if ContainsAny(text, GS.CLASS_POWER_STYLE_PIPS_TERMS) then return "pips" end
    return nil
end

function P.ClassPowerStyleIntent(text)
    return ContainsAny(text, GS.CLASS_POWER_STYLE_INTENT_TERMS)
end

function P.BarsHighlightTab(text)
    if ContainsAny(text, GS.BARS_HIGHLIGHT_MODES_TERMS) then return "modes" end
    if ContainsAny(text, GS.BARS_HIGHLIGHT_PREVIEW_TERMS) then return "preview" end
    if ContainsAny(text, GS.BARS_HIGHLIGHT_PRIORITY_TERMS) then return "priority" end
    return nil
end

function P.BarsHighlightIntent(text)
    return ContainsAny(text, GS.BARS_HIGHLIGHT_INTENT_TERMS)
end

local function ParseMenuSelectorState(text)
    text = tostring(text or "")
    if not ContainsAny(text, GS.MENU_SELECTOR_GATE_TERMS) then
        return nil
    end
    if TextMoveTogetherIntent(text) then
        local textTab = TextSelectorTab(text)
        if textTab == "hp" or textTab == "power" then
            local groups = DetectGroups(text)
            if groups[1] or ContainsAny(text, GS.GROUP_TEXT_TERMS) then
                return MenuSelectorAction({
                    selector = "group_text_move_together",
                    scope = groups[1] or SelectorGroupScope(text),
                    tab = textTab,
                    value = TextMoveTogetherValue(text),
                }, "Set group text move mode")
            end
            local unit = SelectorUnit(text)
            if unit then
                return MenuSelectorAction({
                    selector = "unit_text_move_together",
                    unit = unit,
                    tab = textTab,
                    value = TextMoveTogetherValue(text),
                }, "Set unit text move mode")
            end
        end
    end

    -- Natural value/geometry requests name the slot only to identify the
    -- setting. They must continue to the setting parser instead of stopping
    -- after changing the editor selection (for example "create HP text on the
    -- left with max"). Explicit Select/Choose/Pick verbs remain selectors.
    if not HasMenuSelectorVerb(text)
        and ContainsAny(text, GS.NATURAL_TEXT_SELECTOR_REJECT_TERMS)
    then
        return nil
    end

    local anchorTextTab = TextSelectorTab(text)
    local anchorTextSlot = TextSelectorSlot(text)
    if not anchorTextSlot then anchorTextSlot = NaturalTextSelectorSlot(text) end
    if (anchorTextTab == "hp" or anchorTextTab == "power") and TextSelectorIntent(text, anchorTextTab, anchorTextSlot) then
        local groups = DetectGroups(text)
        if groups[1] or ContainsAny(text, GS.GROUP_TEXT_TERMS) then
            return MenuSelectorAction({
                selector = "group_text",
                scope = groups[1] or SelectorGroupScope(text),
                tab = anchorTextTab,
                slot = anchorTextSlot,
            }, "Select group text choice")
        end
        local unit = SelectorUnit(text)
        if unit then
            return MenuSelectorAction({
                selector = "unit_text",
                unit = unit,
                tab = anchorTextTab,
                slot = anchorTextSlot,
            }, "Select unit text choice")
        end
    end

    local genericMenuSelectorIntent = ContainsAny(text, GS.GENERIC_MENU_SELECTOR_INTENT_TERMS)
    if not HasMenuSelectorVerb(text) and not genericMenuSelectorIntent then return nil end

    local classPowerStyleTab = P.ClassPowerStyleTab(text)
    if classPowerStyleTab and P.ClassPowerStyleIntent(text) then
        return MenuSelectorAction({
            selector = "class_power_style_tab",
            tab = classPowerStyleTab,
        }, "Select Class Resources style tab")
    end

    local barsHighlightTab = P.BarsHighlightTab(text)
    if barsHighlightTab and P.BarsHighlightIntent(text) then
        return MenuSelectorAction({
            selector = "bars_highlight_tab",
            tab = barsHighlightTab,
        }, "Select Highlight Borders tab")
    end

    if ContainsAny(text, GS.CLASS_POWER_COLOR_TOKEN_TERMS)
        or (ContainsAny(text, GS.CLASS_POWER_COLOR_TERMS)
            and ContainsAny(text, GS.CLASS_POWER_RESOURCE_TOKEN_TERMS))
    then
        local token = ClassPowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "classPower", token = token }, "Select class resource color slot")
        end
    end
    if ContainsAny(text, GS.POWER_COLOR_TOKEN_TERMS)
        and not ContainsAny(text, GS.CLASS_POWER_REJECT_TERMS)
    then
        local token = PowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "power", token = token }, "Select power color slot")
        end
    end

    local textTab = TextSelectorTab(text)
    local textSlot = TextSelectorSlot(text)
    if textTab and TextSelectorIntent(text, textTab, textSlot) then
        local groups = DetectGroups(text)
        if groups[1] or ContainsAny(text, GS.GROUP_TEXT_TERMS) then
            return MenuSelectorAction({
                selector = "group_text",
                scope = groups[1] or SelectorGroupScope(text),
                tab = textTab,
                slot = textSlot,
            }, "Select group text choice")
        end
        local unit = SelectorUnit(text)
        if unit then
            return MenuSelectorAction({
                selector = "unit_text",
                unit = unit,
                tab = textTab,
                slot = textSlot,
            }, "Select unit text choice")
        end
    end

    if ContainsAny(text, GS.SPELL_INDICATOR_TERMS) then
        local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(text) or nil
        local aura, resolvedSpec
        if type(A.ResolveGroupSpellAura) == "function" then
            aura, resolvedSpec = A.ResolveGroupSpellAura(spec, text)
        end
        spec = spec or resolvedSpec
        if spec or aura then
            return MenuSelectorAction({
                selector = "group_spell",
                scope = SelectorGroupScope(text),
                spec = spec,
                aura = aura,
                text = text,
            }, "Select group spell indicator")
        end
    end

    if ContainsAny(text, GS.CORNER_EDITOR_TERMS) then
        local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
        if slot then
            return MenuSelectorAction({
                selector = "group_corner",
                scope = SelectorGroupScope(text),
                slot = slot.key or slot.value or text,
                text = text,
            }, "Select group corner editor slot")
        end
    end

    local statusTab = StatusSelectorTab(text)
    local statusIntent = StatusSelectorIntent(text)
    if statusIntent then
        local groups = DetectGroups(text)
        local groupStatusIcon = GroupStatusIconForText(text)
        if groups[1] or ContainsAny(text, GS.GROUP_STATUS_TERMS) then
            if statusTab or groupStatusIcon then
                return MenuSelectorAction({
                    selector = "group_status",
                    scope = groups[1] or SelectorGroupScope(text),
                    tab = statusTab,
                    icon = groupStatusIcon,
                    text = text,
                }, "Select group status icon")
            end
        end

        local unit = SelectorUnit(text)
        local unitStatus = unit and A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text) or nil
        if unit and (statusTab or unitStatus) then
            return MenuSelectorAction({
                selector = "unit_status",
                unit = unit,
                tab = statusTab,
                status = unitStatus and unitStatus.value,
                text = text,
            }, "Select unit status icon")
        end

        if groupStatusIcon then
            return MenuSelectorAction({
                selector = "group_status",
                scope = SelectorGroupScope(text),
                icon = groupStatusIcon,
                text = text,
            }, "Select group status icon")
        end
    end

    if ContainsAny(text, GS.TEXT_SELECTOR_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which frame, text area, and slot or mode do you want me to use? For example: select player hp left slot, select party power text right slot, turn off party hp move text as one group, or use individual player power text units.",
            summary = "Asks which text choice to use.",
        }
    end
    if ContainsAny(text, GS.STATUS_SELECTOR_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which frame and indicator do you want me to use? For example: select target advanced status tab, select party leader icon indicator, or select party ready check icon indicator.",
            summary = "Asks which status indicator to select.",
        }
    end
    if ContainsAny(text, GS.SPELL_INDICATOR_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which group frame and tracked spell slot do you want me to use? For example: select party spell indicator for priest, or select raid tracked spell prayer of mending.",
            summary = "Asks which spell indicator to select.",
        }
    end
    if ContainsAny(text, GS.CORNER_EDITOR_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which corner slot do you want me to use? For example: select bottom right corner editor slot, or select top left corner editor slot.",
            summary = "Asks which corner slot to select.",
        }
    end
    if ContainsAny(text, GS.POWER_COLOR_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which color slot do you want me to use? For example: select mana power color, select rage power color, or select combo point class resource color.",
            summary = "Asks which color slot to select.",
        }
    end
    if ContainsAny(text, GS.CLASS_POWER_STYLE_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which Class Resources Style tab do you want me to open? For example: select class resource style text tab, select class power style opacity tab, or select class power style pips tab.",
            summary = "Asks for the Class Resources style tab.",
        }
    end
    if ContainsAny(text, GS.BARS_HIGHLIGHT_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which Highlight Borders tab do you want me to open? For example: select highlight borders preview tab, select highlight priority tab, or select highlight modes tab.",
            summary = "Asks for the Highlight Borders tab.",
        }
    end
    if ContainsAny(text, GS.PROFILE_STAGING_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which profile value do you want me to prepare? For example: set profile name to Raid Draft, set import profile name to Imported Raid, or set profile import text to MSUF5:....",
            summary = "Asks which profile value to select.",
        }
    end
    if ContainsAny(text, GS.COPY_CATEGORY_QUESTION_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Which copy categories do you want me to set? For example: select only unit copy text and cast bar categories, turn off unit copy portrait category, or select only group copy health and text categories.",
            summary = "Asks which copy details to use.",
        }
    end

    return nil
end


P.MENU_SELECTOR_VERBS = MENU_SELECTOR_VERBS
P.HasMenuSelectorVerb = HasMenuSelectorVerb
P.MenuSelectorAction = MenuSelectorAction
P.SelectorUnit = SelectorUnit
P.SelectorGroupScope = SelectorGroupScope
P.TextMoveTogetherIntent = TextMoveTogetherIntent
P.TextMoveTogetherValue = TextMoveTogetherValue
P.StatusSelectorTab = StatusSelectorTab
P.StatusSelectorIntent = StatusSelectorIntent
P.ParseMenuSelectorState = ParseMenuSelectorState
