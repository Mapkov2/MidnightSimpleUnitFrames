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

-- Menu selector parser for UI-only changes.
-- Selecting a visible tab/dropdown/slot should not mutate the underlying setting value; it
-- only changes the active editor selection so the user lands on the relevant control.
local MENU_SELECTOR_VERBS = {
    "select", "choose", "pick", "open", "show", "switch to", "go to", "edit",
}

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
    if ContainsAny(text, { "individual", "separate", "separately", "each" })
        and ContainsAny(text, { "hp text", "health text", "power text", "mana text" })
        and ContainsAny(text, { "unit", "units", "slot", "slots", "text unit", "text units", "text slot", "text slots" })
    then
        return true
    end
    return ContainsAny(text, {
        "move text as one group", "move as one group", "text as one group",
        "move text together", "text move together", "move together",
        "move text per slot", "text per slot", "per slot", "selected slot mode",
        "individual slot", "individual slots", "separate slot", "separate slots",
        "move text separately", "text separately", "individual text unit", "individual text units",
        "separate text unit", "separate text units", "move individual text", "move each text",
    })
end

local function TextMoveTogetherValue(text)
    if ContainsAny(text, { "individual", "separate", "separately", "each" })
        and ContainsAny(text, { "hp text", "health text", "power text", "mana text" })
        and ContainsAny(text, { "unit", "units", "slot", "slots", "text unit", "text units", "text slot", "text slots" })
    then
        return false
    end
    if ContainsAny(text, {
        "per slot", "selected slot mode", "individual slot", "individual slots",
        "separate slot", "separate slots", "separately", "text separately",
        "individual text unit", "individual text units", "separate text unit", "separate text units",
        "move individual text", "move each text",
    }) then
        return false
    end
    local value = DetectBoolean(text)
    if value ~= nil then return value end
    return true
end

local function NaturalTextSelectorSlot(text)
    if not ContainsAny(text, { "put", "place", "align", "anchor", "anchoring" }) then return nil end
    if ContainsAny(text, {
        "move", "nudge", "shift", "offset", "position", "pos", "x", "y", "up", "down",
        "size", "font size", "layer", "current", "percent", "percentage", "max", "maximum",
        "deficit", "missing", "hide", "clear", "remove", "none", "off",
    }) then
        return nil
    end
    local left = ContainsAny(text, { "left", "links" })
    local center = ContainsAny(text, { "center", "centre", "middle", "mitte" })
    local right = ContainsAny(text, { "right", "rechts" })
    local count = (left and 1 or 0) + (center and 1 or 0) + (right and 1 or 0)
    if count ~= 1 then return nil end
    if left then return "left" end
    if center then return "center" end
    if right then return "right" end
    return nil
end

local function StatusSelectorTab(text)
    if ContainsAny(text, { "advanced status tab", "advanced status icon tab", "advanced indicator tab", "advanced status controls", "advanced status" }) then return "advanced" end
    if ContainsAny(text, { "basic status tab", "basic status icon tab", "basic indicator tab", "basic status controls", "basic status" }) then return "basic" end
    return nil
end

local function StatusSelectorIntent(text)
    if ContainsAny(text, {
        "status tab", "status icon tab", "status indicator tab", "indicator tab",
        "status selector", "status dropdown", "indicator selector", "indicator dropdown",
        "status controls", "status icon controls", "selected indicator",
    }) then
        return true
    end
    return ContainsAny(text, { "indicator", "status icon" })
end

function P.ClassPowerStyleTab(text)
    if ContainsAny(text, { "textures tab", "texture tab", "resources tab", "resource tab", "style textures", "style resources" }) then return "resources" end
    if ContainsAny(text, { "text tab", "style text", "class power text tab", "class resource text tab" }) then return "text" end
    if ContainsAny(text, { "opacity tab", "alpha tab", "transparency tab", "style opacity", "style alpha" }) then return "opacity" end
    if ContainsAny(text, { "pips tab", "pip tab", "separator tab", "separators tab", "style pips" }) then return "pips" end
    return nil
end

function P.ClassPowerStyleIntent(text)
    return ContainsAny(text, {
        "class power style", "class resource style", "class resources style", "class power style tab",
        "class resource style tab", "class resources style area", "class power style area",
    })
end

function P.BarsHighlightTab(text)
    if ContainsAny(text, { "modes tab", "mode tab", "border modes", "highlight modes", "highlight mode" }) then return "modes" end
    if ContainsAny(text, { "preview tab", "test tab", "highlight preview", "highlight test" }) then return "preview" end
    if ContainsAny(text, { "priority tab", "priorities tab", "priority order", "order tab", "highlight priority" }) then return "priority" end
    return nil
end

function P.BarsHighlightIntent(text)
    return ContainsAny(text, {
        "highlight borders tab", "highlight border tab", "highlight borders", "bar highlight tab",
        "bars highlight tab", "highlight area", "highlight border area",
        "highlight modes", "highlight mode", "highlight preview", "highlight test", "highlight priority",
    })
end

local function ParseMenuSelectorState(text)
    text = tostring(text or "")
    if not (text:find("select", 1, true) or text:find("choose", 1, true)
        or text:find("pick", 1, true) or text:find("open", 1, true)
        or text:find("show", 1, true) or text:find("switch", 1, true)
        or text:find("edit", 1, true) or text:find("tab", 1, true)
        or text:find("slot", 1, true) or text:find("selector", 1, true)
        or text:find("dropdown", 1, true) or text:find("status", 1, true)
        or text:find("indicator", 1, true) or text:find("text", 1, true)
        or text:find("put", 1, true) or text:find("place", 1, true)
        or text:find("align", 1, true) or text:find("anchor", 1, true)
        or text:find("class power", 1, true) or text:find("class resource", 1, true)
        or text:find("highlight", 1, true) or text:find("copy", 1, true)
        or text:find("category", 1, true) or text:find("categories", 1, true)
        or text:find("scope", 1, true) or text:find("scopes", 1, true)) then
        return nil
    end
    if TextMoveTogetherIntent(text) then
        local textTab = TextSelectorTab(text)
        if textTab == "hp" or textTab == "power" then
            local groups = DetectGroups(text)
            if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
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

    local anchorTextTab = TextSelectorTab(text)
    local anchorTextSlot = TextSelectorSlot(text)
    if not anchorTextSlot then anchorTextSlot = NaturalTextSelectorSlot(text) end
    if (anchorTextTab == "hp" or anchorTextTab == "power") and TextSelectorIntent(text, anchorTextTab, anchorTextSlot) then
        local groups = DetectGroups(text)
        if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
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

    local genericMenuSelectorIntent = ContainsAny(text, {
        "select text tab", "select text slot", "text move together", "move text as one group", "move text per slot",
        "select status tab", "select status indicator", "select group status icon",
        "select spell indicator", "select corner editor slot",
        "select power color token", "select class resource color token", "select class power color token",
        "select class power style tab", "select class resource style tab", "select class resources style area",
        "select highlight borders tab", "select bars highlight tab", "select highlight area",
        "set profile staging field", "set profile string field",
        "set unit copy category", "select unit copy categories", "set group copy category", "select group copy categories",
    })
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

    if ContainsAny(text, { "class power color token", "class resource color token", "class power token", "class resource token" })
        or (ContainsAny(text, { "class power color", "class resource color", "resource color" })
            and ContainsAny(text, { "combo point", "combo points", "holy power", "soul shard", "soul shards", "chi", "arcane charge", "arcane charges", "runes", "essence", "maelstrom", "astral", "stagger", "ebon", "whirlwind", "tip of the spear", "insanity" }))
    then
        local token = ClassPowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "classPower", token = token }, "Select class resource color slot")
        end
    end
    if ContainsAny(text, { "power color token", "power token", "power type", "resource type", "resource color token" })
        and not ContainsAny(text, { "class power", "class resource", "combo point", "combo points" })
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
        if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
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

    if ContainsAny(text, { "spell indicator selector", "spell indicator dropdown", "spell indicator spec", "tracked spell selector", "tracked spells selector", "tracked spell", "multi spec entry", "multi-spec entry" }) then
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

    if ContainsAny(text, { "corner editor slot", "editor slot", "corner slot", "custom spell editor" }) then
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
        if groups[1] or ContainsAny(text, { "group status", "group indicator", "party indicator", "raid indicator", "mythic raid indicator" }) then
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

    if ContainsAny(text, { "select text tab", "select text slot", "text move together", "move text as one group", "move text per slot" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which frame, text area, and slot or mode do you want me to use? For example: select player hp left slot, select party power text right slot, turn off party hp move text as one group, or use individual player power text units.",
            summary = "Asks which text choice to use.",
        }
    end
    if ContainsAny(text, { "select status tab", "select status indicator", "select group status icon" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which frame and indicator do you want me to use? For example: select target advanced status tab, select party leader icon indicator, or select party ready check icon indicator.",
            summary = "Asks which status indicator to select.",
        }
    end
    if ContainsAny(text, { "select spell indicator" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which group frame and tracked spell slot do you want me to use? For example: select party spell indicator for priest, or select raid tracked spell prayer of mending.",
            summary = "Asks which spell indicator to select.",
        }
    end
    if ContainsAny(text, { "select corner editor slot", "corner editor slot", "editor slot" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which corner slot do you want me to use? For example: select bottom right corner editor slot, or select top left corner editor slot.",
            summary = "Asks which corner slot to select.",
        }
    end
    if ContainsAny(text, { "select power color token", "select class resource color token", "select class power color token" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which color slot do you want me to use? For example: select mana power color, select rage power color, or select combo point class resource color.",
            summary = "Asks which color slot to select.",
        }
    end
    if ContainsAny(text, { "select class power style tab", "select class resource style tab", "class resources style area" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which Class Resources Style tab do you want me to open? For example: select class resource style text tab, select class power style opacity tab, or select class power style pips tab.",
            summary = "Asks for the Class Resources style tab.",
        }
    end
    if ContainsAny(text, { "select highlight borders tab", "select bars highlight tab", "select highlight area" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which Highlight Borders tab do you want me to open? For example: select highlight borders preview tab, select highlight priority tab, or select highlight modes tab.",
            summary = "Asks for the Highlight Borders tab.",
        }
    end
    if ContainsAny(text, { "set profile staging field", "set profile string field" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Which profile value do you want me to prepare? For example: set profile name to Raid Draft, set import profile name to Imported Raid, or set profile import text to MSUF5:....",
            summary = "Asks which profile value to select.",
        }
    end
    if ContainsAny(text, { "set unit copy category", "select unit copy categories", "set group copy category", "select group copy categories" }) then
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
