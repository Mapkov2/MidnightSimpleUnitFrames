-- Assistant geometry-text parser: parses text slot, offset, layer, and alignment commands.
-- Produces parser plans only; DB writes and apply side effects remain in Assistant execution.
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
local Data = A.ParserData or {}
A.ParserData = Data
local GeometryTextData = Data.GEOMETRY_TEXT_PARSER or {}
local GeometryTextPhrases = GeometryTextData.PHRASES or {}
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local OFF_WORDS = P.OFF_WORDS
local FirstNumber = P.FirstNumber
local DetectDirection = P.DetectDirection
local DetectBoolean = P.DetectBoolean
local RelativeNumberDeltaForText = P.RelativeNumberDeltaForText
local EnumValueForText = P.EnumValueForText
local CurrentPageUnit = P.CurrentPageUnit
local GroupScopesOrCurrentPage = P.GroupScopesOrCurrentPage

local function ReadSettingValue(setting)
    if not (setting and type(setting.get) == "function") then return nil end
    local ok, value = pcall(setting.get)
    if ok then return value end
    return nil
end

local function PositionTextKind(text)
    if ContainsAny(text, { "power text", "mana text", "power number", "mana number" }) then return "power" end
    if ContainsAny(text, { "hp text", "health text", "hp number", "health number" }) then return "hp" end
    if ContainsAny(text, { "name text", "unit name" }) then return "name" end
    return nil
end

function A._ParseUnitTextPositionCopyShortcut(text)
    if not ContainsAny(text, { "position of", "same position as", "position from" }) then return nil end
    local destinationText, sourceText = text:match("^move%s+(.+)%s+to%s+the%s+position%s+of%s+(.+)$")
    if not destinationText then destinationText, sourceText = text:match("^move%s+(.+)%s+to%s+position%s+of%s+(.+)$") end
    if not destinationText then destinationText, sourceText = text:match("^put%s+(.+)%s+at%s+the%s+same%s+position%s+as%s+(.+)$") end
    if not destinationText then return nil end
    local destinationKind, sourceKind = PositionTextKind(destinationText), PositionTextKind(sourceText)
    if not destinationKind or not sourceKind or destinationKind == sourceKind then return nil end
    local units = DetectUnits(text)
    if #units ~= 1 then
        return { kind = "answer", status = "ambiguous", text = "Which single Unit Frame should copy that text position? Example: move target power text to the position of target HP text.", summary = "Requires one Unit Frame for an internal text-position copy." }
    end
    local unit = units[1]
    local attrs = {
        hp = { "hpOffsetX", "hpOffsetY" },
        power = { "powerOffsetX", "powerOffsetY" },
        name = { "nameOffsetX", "nameOffsetY" },
    }
    local sourceAttrs, destinationAttrs = attrs[sourceKind], attrs[destinationKind]
    local changes = {}
    for axis = 1, 2 do
        local sourceSetting = Registry and Registry:GetSetting(tostring(unit) .. "." .. sourceAttrs[axis])
        local destinationSetting = Registry and Registry:GetSetting(tostring(unit) .. "." .. destinationAttrs[axis])
        local value = ReadSettingValue(sourceSetting)
        if destinationSetting and type(value) == "number" then changes[#changes + 1] = { setting = destinationSetting, value = value } end
    end
    if #changes ~= 2 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = true,
        label = "Copy " .. sourceKind .. " text position to " .. destinationKind .. " text",
        summary = "Copies both X and Y text offsets within the selected Unit Frame as one undoable change.",
    }
end

local function DisplayValue(setting, value)
    if P and type(P.ValueDisplay) == "function" then
        local label = P.ValueDisplay(setting, value)
        if label ~= nil then return tostring(label) end
    end
    if value == "NONE" then return "none" end
    if setting and (setting.type == "enum" or type(setting.values) == "table") and type(A.HumanizeDisplayKey) == "function" then
        return A.HumanizeDisplayKey(value)
    end
    return tostring(value)
end

-- Text geometry parser helpers.
-- These identify text tabs, anchor slots, and font-size/offset intent before the broader
-- geometry parser maps the result to settings.
local function TextSelectorTab(text)
    if ContainsAny(text, GeometryTextPhrases[1]) then return "advanced" end
    if ContainsAny(text, GeometryTextPhrases[2]) then return "power" end
    if ContainsAny(text, GeometryTextPhrases[3]) then return "hp" end
    if ContainsAny(text, GeometryTextPhrases[4]) then return "name" end
    return nil
end

local function TextSelectorSlot(text)
    if ContainsAny(text, GeometryTextPhrases[5])
        or (HasPhrase(text, "left") and ContainsAny(text, GeometryTextPhrases[6]))
    then
        return "left"
    end
    if ContainsAny(text, GeometryTextPhrases[7])
        or ContainsAny(text, GeometryTextPhrases[8])
        or ((HasPhrase(text, "center") or HasPhrase(text, "centre") or HasPhrase(text, "middle")) and ContainsAny(text, GeometryTextPhrases[9]))
    then
        return "center"
    end
    if ContainsAny(text, GeometryTextPhrases[10])
        or (HasPhrase(text, "right") and ContainsAny(text, GeometryTextPhrases[11]))
    then
        return "right"
    end
    return nil
end

local function TextSelectorIntent(text, tab, slot)
    if ContainsAny(text, GeometryTextPhrases[112]) then return false end
    if FirstNumber(text) ~= nil and ContainsAny(text, GeometryTextPhrases[113]) then return false end
    if tab == "name" and ContainsAny(text, GeometryTextPhrases[12]) then return false end
    if (tab == "hp" or tab == "power") and slot and ContainsAny(text, GeometryTextPhrases[13]) then return true end
    if ContainsAny(text, GeometryTextPhrases[14]) then
        return true
    end
    return tab and ContainsAny(text, GeometryTextPhrases[15]) and (HasPhrase(text, "tab") or slot ~= nil)
end

local function TextFontSizeIntent(text)
    if ContainsAny(text, GeometryTextPhrases[16]) then
        return true
    end
    if not ContainsAny(text, GeometryTextPhrases[17]) then
        return false
    end
    return ContainsAny(text, GeometryTextPhrases[18])
end

function A._ParseTextFontSizeShortcut(text)
    if ContainsAny(text, GeometryTextPhrases[19]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[20]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[21]) then
        return nil
    end
    local allTextIntent = ContainsAny(text, GeometryTextPhrases[22]) and ContainsAny(text, GeometryTextPhrases[23])
    local broadGenericTextIntent = ContainsAny(text, GeometryTextPhrases[17])
        and ContainsAny(text, { "text", "font" })
    if not allTextIntent and not TextFontSizeIntent(text) and not broadGenericTextIntent then
        return nil
    end
    local tab = TextSelectorTab(text)
    local allText = tab == nil and allTextIntent
    local genericText = tab == nil and not allText and broadGenericTextIntent
    if tab ~= "name" and tab ~= "hp" and tab ~= "power" and not allText and not genericText then return nil end

    local attrs
    if allText or genericText then
        attrs = { "nameFontSize", "hpFontSize", "powerFontSize" }
    else
        attrs = { tab == "name" and "nameFontSize" or (tab == "hp" and "hpFontSize" or "powerFontSize") }
    end
    local relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
    local value
    if relativeDelta == nil then value = FirstNumber(text) end
    if value == nil and relativeDelta == nil then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end

    local changes = {}
    for i = 1, #groups do
        for j = 1, #attrs do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attrs[j])
            if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
        end
    end
    for i = 1, #units do
        for j = 1, #attrs do
            local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attrs[j])
            if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
        end
    end
    if #changes == 0 then return nil end
    if genericText and #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which text should change size?",
            summary = "Offers Name, HP, and Power text-size options instead of guessing which text the user meant.",
        }
    end
    if #changes > 1 and #groups > 1 and not allText then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching group text font-size options",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = allText and "Set all text font sizes" or "Set text font size",
        bulkSafe = allText and #changes > 1 or nil,
        summary = allText
            and "Changes only the Name, HP, and Power text font-size sliders for the selected unit or group scope."
            or "Changes the Name/HP/Power text font-size slider for the selected unit or group scope.",
    }
end

function A._ParseTextLayerShortcut(text)
    if ContainsAny(text, GeometryTextPhrases[24]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[25]) then return nil end
    if not ContainsAny(text, GeometryTextPhrases[26]) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "name" and tab ~= "hp" and tab ~= "power" then return nil end

    local relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
    if relativeDelta == nil then
        if ContainsAny(text, GeometryTextPhrases[27]) then
            relativeDelta = 1
        elseif ContainsAny(text, GeometryTextPhrases[28]) then
            relativeDelta = -1
        end
    end
    local value
    if relativeDelta == nil then value = FirstNumber(text) end
    if value == nil and relativeDelta == nil then return nil end

    local unitAttr = tab == "name" and "nameTextLayer" or (tab == "hp" and "hpTextLayer" or "powerTextLayer")
    local groupAttr = tab == "name" and "nameTextLayer" or (tab == "hp" and "textLayer" or "powerTextLayer")
    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
        if #groups == 0 and #units == 0 then
            local ctx = A.GetContext and A.GetContext() or nil
            local currentTurn = type(ctx) == "table" and (tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0) or 0
            local subjectTurn = type(ctx) == "table" and tonumber(ctx.lastSubjectTurn or ctx.lastMentionedTurn) or nil
            local contextualUnit = type(ctx) == "table" and ctx.lastUnit or nil
            if contextualUnit and subjectTurn and currentTurn - subjectTurn <= 1 then
                units = { contextualUnit }
            end
        end
    end

    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. groupAttr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. unitAttr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #groups > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching group text-layer options",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text layer",
        summary = "Changes the Name/HP/Power text layer for the selected unit or group.",
    }
end

function A._TextSlotForDetail(text, tab)
    if tab ~= "hp" and tab ~= "power" then return nil end
    if tab == "hp" then
        if ContainsAny(text, GeometryTextPhrases[29]) then return "Left" end
        if ContainsAny(text, GeometryTextPhrases[30]) then return "Center" end
        if ContainsAny(text, GeometryTextPhrases[31]) then return "Right" end
    else
        if ContainsAny(text, GeometryTextPhrases[32]) then return "Left" end
        if ContainsAny(text, GeometryTextPhrases[33]) then return "Center" end
        if ContainsAny(text, GeometryTextPhrases[34]) then return "Right" end
    end
    if ContainsAny(text, GeometryTextPhrases[35]) then return "Left" end
    if ContainsAny(text, GeometryTextPhrases[36]) then return "Center" end
    if ContainsAny(text, GeometryTextPhrases[37]) then return "Right" end
    local slot = TextSelectorSlot(text)
    if (slot == "left" or slot == "center" or slot == "right")
        and ContainsAny(text, GeometryTextPhrases[38])
    then
        return slot == "left" and "Left" or (slot == "right" and "Right" or "Center")
    end
    return nil
end

function A._TextSlotName(slot)
    slot = tostring(slot or ""):lower()
    if slot == "left" then return "Left" end
    if slot == "center" or slot == "centre" or slot == "middle" then return "Center" end
    if slot == "right" then return "Right" end
    return nil
end

function A._TextSlotLower(slot)
    slot = A._TextSlotName(slot)
    if slot == "Left" then return "left" end
    if slot == "Center" then return "center" end
    if slot == "Right" then return "right" end
    return nil
end

function A._BareTextSlotForValueText(text)
    if ContainsAny(text, GeometryTextPhrases[39]) then
        return nil
    end
    local left = ContainsAny(text, GeometryTextPhrases[40])
    local center = ContainsAny(text, GeometryTextPhrases[41])
    local right = ContainsAny(text, GeometryTextPhrases[42])
    local count = (left and 1 or 0) + (center and 1 or 0) + (right and 1 or 0)
    if count ~= 1 then return nil end
    if left then return "Left" end
    if center then return "Center" end
    if right then return "Right" end
    return nil
end

function A._TextSlotSettingKey(tab, slot)
    slot = A._TextSlotName(slot)
    if not slot then return nil end
    if tab == "hp" then
        return slot == "Left" and "textLeft" or (slot == "Center" and "textCenter" or "textRight")
    elseif tab == "power" then
        return "powerText" .. slot
    end
    return nil
end

local function ReadSettingValue(setting)
    if setting and type(setting.get) == "function" then
        return setting.get()
    end
    return nil
end

local function TextSlotSetting(frameType, unitOrScope, tab, slotName)
    local keyName = A._TextSlotSettingKey(tab, slotName)
    if not keyName or not Registry then return nil end
    local prefix = frameType == "group" and ("gf_" .. tostring(unitOrScope)) or tostring(unitOrScope)
    return Registry:GetSetting(prefix .. "." .. keyName)
end

local function ActiveTextSlotsForTarget(frameType, unitOrScope, tab)
    local active = {}
    for _, slotName in ipairs({ "Left", "Center", "Right" }) do
        local setting = TextSlotSetting(frameType, unitOrScope, tab, slotName)
        local value = ReadSettingValue(setting)
        if setting and value ~= nil and value ~= "NONE" then
            active[#active + 1] = slotName
        end
    end
    return active
end

local function InferSingleActiveTextSlot(frameType, unitOrScope, tab)
    local active = ActiveTextSlotsForTarget(frameType, unitOrScope, tab)
    return #active == 1 and active[1] or nil, active
end

function A._TextGroupScopeName(scope)
    scope = tostring(scope or "")
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

function A._SelectedTextSlotFromContext(frameType, unitOrScope, tab)
    if tab ~= "hp" and tab ~= "power" then return nil end
    if frameType == "group" then unitOrScope = A._TextGroupScopeName(unitOrScope) end
    local ctx = A.GetContext and A.GetContext() or nil
    local selected = ctx and ctx.selectedTextEditorTarget
    if type(selected) == "table"
        and selected.tab == tab
        and selected.frameType == frameType
        and tostring(frameType == "group" and A._TextGroupScopeName(selected.unit) or selected.unit or "") == tostring(unitOrScope or "")
    then
        return A._TextSlotName(selected.slot)
    end
    if ctx and ctx.lastTextArea == tab
        and ctx.lastTextFrameType == frameType
        and tostring(frameType == "group" and A._TextGroupScopeName(ctx.lastTextUnit) or ctx.lastTextUnit or "") == tostring(unitOrScope or "")
    then
        return A._TextSlotName(ctx.lastTextSlot)
    end
    if frameType == "group" then
        local byScope = M and M.gfTextSlotSelection and M.gfTextSlotSelection[unitOrScope]
        return A._TextSlotName(byScope and byScope[tab])
    end
    local byUnit = M and M.unitTextSlotSelection and M.unitTextSlotSelection[unitOrScope]
    return A._TextSlotName(byUnit and byUnit[tab])
end

function A._SelectedTextTargetFromContext(tab)
    local ctx = A.GetContext and A.GetContext() or nil
    local selected = ctx and ctx.selectedTextEditorTarget
    if type(selected) == "table" and (not tab or selected.tab == tab) then
        return selected.frameType, selected.frameType == "group" and A._TextGroupScopeName(selected.unit) or selected.unit, selected.tab, A._TextSlotName(selected.slot)
    end
    if ctx and ctx.lastTextArea and (not tab or ctx.lastTextArea == tab) then
        return ctx.lastTextFrameType, ctx.lastTextFrameType == "group" and A._TextGroupScopeName(ctx.lastTextUnit) or ctx.lastTextUnit, ctx.lastTextArea, A._TextSlotName(ctx.lastTextSlot)
    end
    return nil
end

function A._ParseNameTextAnchorShortcut(text)
    if ContainsAny(text, GeometryTextPhrases[43]) then
        return nil
    end
    if ContainsAny(text, GeometryTextPhrases[44]) then return nil end

    local tab = TextSelectorTab(text)
    if tab == "hp" or tab == "power" or tab == "advanced" then return nil end
    if ContainsAny(text, GeometryTextPhrases[45]) and not ContainsAny(text, GeometryTextPhrases[46]) then
        return nil
    end

    -- "Move/shift/nudge the name to the left" is a position (X/Y offset) request,
    -- not a text anchor.  Without this, the movement verb plus a directional
    -- phrase like "to the left" would silently set the Name Text Anchor to LEFT
    -- instead of moving the name.  Two intents stay on the anchor path:
    --   * an explicit anchor/align word ("align left", "anchor left"), and
    --   * centering ("move name to middle/center"), which has no offset axis and
    --     is the reviewed meaning of the Name Text Anchor CENTER value.
    -- So only a movement verb aimed at a left/right/up/down direction hands the
    -- request to the offset path.
    if type(A.HasNudgeMovementVerb) == "function" and A.HasNudgeMovementVerb(text)
        and not ContainsAny(text, GeometryTextPhrases[49])
        and not ContainsAny(text, GeometryTextPhrases[47])
    then
        return nil
    end

    local value
    if HasPhrase(text, "top left") or HasPhrase(text, "upper left") then
        value = "TOPLEFT"
    elseif HasPhrase(text, "top center") or HasPhrase(text, "top centre")
        or HasPhrase(text, "upper center") or HasPhrase(text, "upper centre")
    then
        value = "TOP"
    elseif HasPhrase(text, "top right") or HasPhrase(text, "upper right") then
        value = "TOPRIGHT"
    elseif ContainsAny(text, GeometryTextPhrases[47]) then
        value = "CENTER"
    elseif ContainsAny(text, GeometryTextPhrases[48]) or (HasPhrase(text, "left") and ContainsAny(text, GeometryTextPhrases[49])) then
        value = "LEFT"
    elseif ContainsAny(text, GeometryTextPhrases[50]) or (HasPhrase(text, "right") and ContainsAny(text, GeometryTextPhrases[51])) then
        value = "RIGHT"
    end
    if not value then return nil end

    local ctx = A.GetContext and A.GetContext() or nil
    local contextReference = ContainsAny(text, GeometryTextPhrases[52])
    local explicitName = tab == "name" or ContainsAny(text, GeometryTextPhrases[53])
    local genericText = tab == nil
        and ContainsAny(text, GeometryTextPhrases[54])
        and ContainsAny(text, GeometryTextPhrases[55])
    local placementIntent = ContainsAny(text, GeometryTextPhrases[56])
    if not placementIntent then return nil end
    if not explicitName and not genericText and not contextReference then return nil end

    local function IsNameContext(key, attr)
        key = tostring(key or "")
        attr = tostring(attr or "")
        if attr == "name" or attr == "showName" or attr == "nameTextAnchor" or attr == "nameAnchor"
            or attr == "nameOffsetX" or attr == "nameOffsetY" or attr == "nameFontSize" or attr == "nameTextLayer"
        then
            return true
        end
        return key:find(".showName", 1, true)
            or key:find(".nameTextAnchor", 1, true)
            or key:find(".nameAnchor", 1, true)
            or key:find(".nameOffsetX", 1, true)
            or key:find(".nameOffsetY", 1, true)
            or key:find(".nameFontSize", 1, true)
            or key:find(".nameTextLayer", 1, true)
    end

    local function ContextNameTarget()
        if not ctx then return nil, nil end
        if IsNameContext(ctx.lastSetting, ctx.lastAttribute)
            and (ctx.lastFrameType == "unitframe" or ctx.lastFrameType == "group")
            and type(ctx.lastUnit) == "string" and ctx.lastUnit ~= ""
        then
            return ctx.lastFrameType, ctx.lastFrameType == "group" and A._TextGroupScopeName(ctx.lastUnit) or ctx.lastUnit
        end
        local bundle = ctx.lastChangeBundle
        if type(bundle) ~= "table" then return nil, nil end
        for i = #bundle, 1, -1 do
            local item = bundle[i]
            if type(item) == "table" and IsNameContext(item.key, item.attribute)
                and (item.frameType == "unitframe" or item.frameType == "group")
                and type(item.unit) == "string" and item.unit ~= ""
            then
                return item.frameType, item.frameType == "group" and A._TextGroupScopeName(item.unit) or item.unit
            end
        end
        return nil, nil
    end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 and contextReference then
        local frameType, unitOrScope = ContextNameTarget()
        if frameType == "group" then
            groups = { unitOrScope }
        elseif frameType == "unitframe" then
            units = { unitOrScope }
        elseif not explicitName and not genericText then
            return nil
        end
    end

    if #groups == 0 and #units == 0 and not contextReference then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end

    if #groups == 0 and #units == 0 then return nil end

    local changes = {}
    local function AddTarget(settingKey, showKey)
        -- The anchor change is the request; enabling Show Name is only a
        -- companion so the newly anchored name is visible.  Resolve the anchor
        -- first and, when it is valid, add the anchor change BEFORE the Show
        -- Name toggle so the anchor is the primary/reported change.  If the
        -- anchor is not valid, do not add a bare Show Name toggle (that would
        -- turn "anchor name left" into "show name").
        local setting = Registry and Registry:GetSetting(settingKey)
        local targetValue = value
        if tostring(settingKey):find(".nameTextAnchor", 1, true) then
            targetValue = ({ LEFT = "FRAMELEFT", CENTER = "FRAMECENTER", RIGHT = "FRAMERIGHT" })[value] or value
        end
        if not (setting and A._EnumAllowsValue(setting, targetValue)) then return end
        changes[#changes + 1] = {
            setting = setting,
            value = targetValue,
            valueLabel = DisplayValue(setting, targetValue),
        }
        local showSetting = Registry and Registry:GetSetting(showKey)
        if showSetting and ReadSettingValue(showSetting) == false then
            changes[#changes + 1] = {
                setting = showSetting,
                value = true,
                valueLabel = "enabled",
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(showSetting, "enabled", "Name") or (tostring(showSetting.label or "Name") .. ": enabled"),
            }
        end
    end

    for i = 1, #groups do
        local scope = A._TextGroupScopeName(groups[i])
        AddTarget("gf_" .. tostring(scope) .. ".nameAnchor", "gf_" .. tostring(scope) .. ".showName")
    end
    for i = 1, #units do
        local unit = tostring(units[i])
        AddTarget(unit .. ".nameTextAnchor", unit .. ".showName")
    end

    if #changes == 0 then return nil end
    if #changes > 1 and (#groups + #units) > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching name text anchor options",
            summary = "The request matched more than one Name anchor option, so the Assistant is asking which option to change.",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set name text anchor",
        summary = "Changes the Name anchor for the selected unit or group.",
    }
end

-- Genuine anchor-vs-position ambiguity.  "Player name to the left" — a name plus
-- a left/right direction, with no movement verb ("move/shift") and no explicit
-- anchor/align word — could mean either "left-align the name" (Name Text Anchor)
-- or "move the name left" (Name X Offset).  Neither the anchor nor the offset
-- shortcut claims it (both require a verb), so today it falls through to a
-- generic no-match.  Instead of silently guessing, offer both and let the user
-- pick.  Read-only until the user chooses; the status is "ambiguous".
function A._ParseNameDirectionAmbiguityShortcut(text)
    if type(A.HasNudgeMovementVerb) == "function" and A.HasNudgeMovementVerb(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[49]) then return nil end -- explicit anchor/align -> anchor path owns it
    if not ContainsAny(text, GeometryTextPhrases[59]) then return nil end -- must mention a name

    local value
    if ContainsAny(text, GeometryTextPhrases[48]) or HasPhrase(text, "left") then
        value = "LEFT"
    elseif ContainsAny(text, GeometryTextPhrases[50]) or HasPhrase(text, "right") then
        value = "RIGHT"
    end
    if not value then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 then
        local pageUnit = CurrentPageUnit and CurrentPageUnit()
        if pageUnit then units = { pageUnit } end
    end
    if (#groups + #units) ~= 1 then return nil end

    local scope, anchorKey, offsetKey
    if #units == 1 then
        scope = tostring(units[1])
        anchorKey, offsetKey = scope .. ".nameTextAnchor", scope .. ".nameOffsetX"
    else
        scope = "gf_" .. tostring(A._TextGroupScopeName(groups[1]))
        anchorKey, offsetKey = scope .. ".nameAnchor", scope .. ".nameOffsetX"
    end
    local anchorSetting = Registry and Registry:GetSetting(anchorKey)
    local offsetSetting = Registry and Registry:GetSetting(offsetKey)
    if not (anchorSetting and offsetSetting) then return nil end
    local anchorValue = value
    if #units == 1 then
        anchorValue = ({ LEFT = "FRAMELEFT", RIGHT = "FRAMERIGHT" })[value] or value
    end
    if not A._EnumAllowsValue(anchorSetting, anchorValue) then return nil end

    local moveStep = tonumber(offsetSetting.moveStep or offsetSetting.step) or 10
    local delta = value == "LEFT" and -math.abs(moveStep) or math.abs(moveStep)
    local lower = tostring(value):lower()
    return {
        kind = "ambiguous",
        choices = {
            {
                setting = anchorSetting,
                value = anchorValue,
                valueLabel = DisplayValue(anchorSetting, anchorValue),
                label = "Align the name " .. lower .. " (" .. tostring(anchorSetting.label or "Name Text Anchor") .. ")",
            },
            {
                setting = offsetSetting,
                relativeDelta = delta,
                direction = value == "LEFT" and "left" or "right",
                label = "Move the name " .. lower .. " (" .. tostring(offsetSetting.label or "Name X Offset") .. ")",
            },
        },
        label = "Do you want to align the name or move it " .. lower .. "?",
        summary = "Name direction request is ambiguous between anchor and position; asking which the user means.",
    }
end

function A._ParseNameTextOffsetShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[57]) then
        return nil
    end
    if ContainsAny(text, GeometryTextPhrases[58]) then
        return nil
    end
    if not ContainsAny(text, GeometryTextPhrases[59]) then
        return nil
    end
    if not ContainsAny(text, GeometryTextPhrases[60]) then
        return nil
    end

    local axis = A._DetailOffsetAxis and A._DetailOffsetAxis(text) or nil
    local direction
    if ContainsAny(text, GeometryTextPhrases[61]) then
        direction = "down"
    elseif ContainsAny(text, GeometryTextPhrases[62]) then
        direction = "up"
    else
        direction = DetectDirection(text, {})
    end
    if not axis and direction then
        axis = (direction == "left" or direction == "right") and "x" or "y"
    end
    if not axis then return nil end

    local value
    local relativeDelta
    if ContainsAny(text, GeometryTextPhrases[63]) and direction then
        relativeDelta = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then relativeDelta = -relativeDelta end
    else
        value = FirstNumber(text)
    end
    if value == nil and relativeDelta == nil then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #groups == 0 and #units == 0 then return nil end

    local attr = axis == "x" and "nameOffsetX" or "nameOffsetY"
    local changes = {}
    for i = 1, #groups do
        local scope = A._TextGroupScopeName(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Move name text",
        summary = "Changes the Name text offset for the selected unit or group.",
    }
end

function A._ParseNameTextVerticalPlacementShortcut(text)
    if ContainsAny(text, GeometryTextPhrases[64]) then
        return nil
    end
    if not ContainsAny(text, GeometryTextPhrases[65]) then
        return nil
    end
    if not ContainsAny(text, GeometryTextPhrases[66]) then return nil end
    local verticalAnchorIntent = ContainsAny(text, GeometryTextPhrases[67])
        and ContainsAny(text, GeometryTextPhrases[68])
    if not verticalAnchorIntent and not ContainsAny(text, GeometryTextPhrases[69]) then return nil end

    local direction
    if ContainsAny(text, GeometryTextPhrases[70])
        or (verticalAnchorIntent and ContainsAny(text, GeometryTextPhrases[71]))
    then
        direction = "up"
    elseif ContainsAny(text, GeometryTextPhrases[72])
        or (verticalAnchorIntent and ContainsAny(text, GeometryTextPhrases[73]))
    then
        direction = "down"
    end
    if not direction then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #groups == 0 and #units == 0 then return nil end

    local amount = FirstNumber(text) or 10
    if direction == "down" then amount = -amount end
    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".nameOffsetY")
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".nameOffsetY")
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #groups > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching name text vertical offsets",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Move name text vertically",
        summary = "Moves Name text above or below the frame.",
    }
end

function A._EnumAllowsValue(setting, value)
    local values = setting and setting.values
    if type(values) ~= "table" then return false end
    for i = 1, #values do
        if values[i] == value then return true end
    end
    return false
end

function A._TextSlotDropdownValueForText(setting, text)
    local aliases = {
        { "current max percent", "CURMAXPERCENT" },
        { "current maximum percent", "CURMAXPERCENT" },
        { "current max percentage", "CURMAXPERCENT" },
        { "current maximum percentage", "CURMAXPERCENT" },
        { "percent current max", "PERCENTCURMAX" },
        { "percent current maximum", "PERCENTCURMAX" },
        { "percent max current", "PERCENTCURMAX" },
        { "percent maximum current", "PERCENTCURMAX" },
        { "current and max", "CURMAX" },
        { "current and maximum", "CURMAX" },
        { "current/max", "CURMAX" },
        { "current / max", "CURMAX" },
        { "current max", "CURMAX" },
        { "current maximum", "CURMAX" },
        { "current and percent", "CURPERCENT" },
        { "current and percentage", "CURPERCENT" },
        { "current/percent", "CURPERCENT" },
        { "current / percent", "CURPERCENT" },
        { "current percent", "CURPERCENT" },
        { "current percentage", "CURPERCENT" },
        { "max percent", "MAXPERCENT" },
        { "maximum percent", "MAXPERCENT" },
        { "max percentage", "MAXPERCENT" },
        { "maximum percentage", "MAXPERCENT" },
        { "percent current", "PERCENTCUR" },
        { "percentage current", "PERCENTCUR" },
        { "percent max", "PERCENTMAX" },
        { "percentage max", "PERCENTMAX" },
        { "percent maximum", "PERCENTMAX" },
        { "percentage maximum", "PERCENTMAX" },
        { "current health", "CURRENT" },
        { "current hp", "CURRENT" },
        { "hp current", "CURRENT" },
        { "health current", "CURRENT" },
        { "current power", "CURRENT" },
        { "current mana", "CURRENT" },
        { "power current", "CURRENT" },
        { "mana current", "CURRENT" },
        { "current", "CURRENT" },
        { "actual", "CURRENT" },
        { "max health", "MAX" },
        { "maximum health", "MAX" },
        { "health max", "MAX" },
        { "health maximum", "MAX" },
        { "max hp", "MAX" },
        { "maximum hp", "MAX" },
        { "hp max", "MAX" },
        { "hp maximum", "MAX" },
        { "max power", "MAX" },
        { "maximum power", "MAX" },
        { "power max", "MAX" },
        { "power maximum", "MAX" },
        { "max mana", "MAX" },
        { "maximum mana", "MAX" },
        { "mana max", "MAX" },
        { "mana maximum", "MAX" },
        { "maximum", "MAX" },
        { "max", "MAX" },
        { "missing health", "DEFICIT" },
        { "missing hp", "DEFICIT" },
        { "health deficit", "DEFICIT" },
        { "hp deficit", "DEFICIT" },
        { "deficit", "DEFICIT" },
        { "missing", "DEFICIT" },
        { "only %", "PERCENT" },
        { "% only", "PERCENT" },
        { "%", "PERCENT" },
        { "only percent", "PERCENT" },
        { "only percentage", "PERCENT" },
        { "just percent", "PERCENT" },
        { "just percentage", "PERCENT" },
        { "percent only", "PERCENT" },
        { "percentage only", "PERCENT" },
        { "percentage", "PERCENT" },
        { "percent", "PERCENT" },
        { "pct", "PERCENT" },
        { "clear", "NONE" },
        { "remove", "NONE" },
        { "removed", "NONE" },
        { "nothing", "NONE" },
        { "empty", "NONE" },
        { "none", "NONE" },
        { "hidden", "NONE" },
        { "hide", "NONE" },
        { "off", "NONE" },
    }
    for i = 1, #aliases do
        local alias, value = aliases[i][1], aliases[i][2]
        if HasPhrase(text, alias) then
            if A._EnumAllowsValue(setting, value) then return value end
            return nil, value
        end
    end
    local value = EnumValueForText(setting, text)
    if value ~= nil and A._EnumAllowsValue(setting, value) then return value end
    return nil
end

P.TEXT_SLOT_SHOW_INTENT_TERMS = {
    "show", "display", "visible", "add", "create", "create new", "new", "put",
    "turn on", "enable", "enabled",
    "anzeigen", "zeigen", "einblenden", "sichtbar", "aktivieren", "einschalten",
}

function A._HasTextSlotShowIntent(text)
    if ContainsAny(text, OFF_WORDS) then return false end
    return ContainsAny(text, P.TEXT_SLOT_SHOW_INTENT_TERMS)
end

function A._AddTextSlotVisibilityChange(out, frameType, unitOrScope, tab)
    if tab ~= "hp" and tab ~= "power" then return end
    local key
    if frameType == "group" then
        key = "gf_" .. tostring(A._TextGroupScopeName(unitOrScope)) .. "." .. (tab == "hp" and "showHPText" or "showPowerText")
    else
        key = tostring(unitOrScope) .. "." .. (tab == "hp" and "showHP" or "showPowerText")
    end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return end
    out[#out + 1] = {
        setting = setting,
        value = true,
        valueLabel = "on",
        textArea = tab,
        label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, "on", "Text visibility") or (tostring(setting.label or "Text visibility") .. ": on"),
    }
end

local function TextSlotMoveValueIntent(text)
    return ContainsAny(text, GeometryTextPhrases[74])
end

function A._ParseTextSlotDropdownValueShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[75]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[76]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[77]) then
        return nil
    end
    if ContainsAny(text, {
        "bigger", "larger", "smaller", "increase", "decrease",
        "font", "font size", "text size",
    }) then
        return nil
    end

    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then
        -- "Show percentages instead of numbers" names only the display mode --
        -- not the text area, the slot, or the frame. It is still a real
        -- request, so name the three things that are missing instead of
        -- dropping it into a generic examples list. Kept deliberately narrow:
        -- a bare mode word plus a display verb, with nothing else identified.
        if #DetectUnits(text) > 0 or #DetectGroups(text) > 0 then return nil end
        if not ContainsAny(text, { "percent", "percentage", "percentages", "prozent", "prozentzahl" }) then return nil end
        if not ContainsAny(text, { "show", "display", "use", "instead", "statt", "zeige", "anzeigen" }) then return nil end
        if ContainsAny(text, {
            "aura", "buff", "debuff", "castbar", "cast bar", "class power", "class resource",
            "range", "fade", "scale", "size", "font", "color", "colour", "opacity", "alpha",
        }) then
            return nil
        end
        return {
            kind = "unknown",
            status = "failed",
            text = "I can switch text between percentages and numbers, but I need to know where."
                .. "\nEach frame has a left, center, and right slot for health text and for power text."
                .. "\nTell me the frame and the slot, for example 'set player hp right slot to percent'"
                .. " or 'set raid health text to percent'.",
            summary = "Asks which text area, slot, and frame a percent/number mode applies to.",
        }
    end
    local slot = A._TextSlotForDetail(text, tab)
    local hasExplicitFrame = #DetectUnits(text) > 0 or #DetectGroups(text) > 0
    if not slot and hasExplicitFrame then
        local bareSlot = TextSelectorSlot(text)
        if not bareSlot then
            if ContainsAny(text, GeometryTextPhrases[40]) then bareSlot = "left"
            elseif ContainsAny(text, GeometryTextPhrases[41]) then bareSlot = "center"
            elseif ContainsAny(text, GeometryTextPhrases[42]) then bareSlot = "right" end
        end
        if bareSlot == "left" then slot = "Left"
        elseif bareSlot == "center" then slot = "Center"
        elseif bareSlot == "right" then slot = "Right" end
    end
    if not slot and A._HasTextSlotShowIntent(text) and hasExplicitFrame then
        -- Existing natural shorthand uses the right slot when the frame,
        -- health/power area, display mode, and explicit show intent are all
        -- present ("show target health as current and percent").
        slot = "right"
    end
    if not slot then
        if ContainsAny(text, { "it", "that", "this", "now" }) then
            -- Contextual follow-ups are owned by the later follow-up parser,
            -- which can reuse the previously selected frame and slot.
            return nil
        end
        -- "Show percentages instead of numbers" names the mode but neither the
        -- slot nor the frame. It is a real, understandable request, so say what
        -- is missing rather than falling through to a generic examples list.
        -- A text slot mode is an enum word, so a request carrying an explicit
        -- number is setting something else and only borrowed the mode word.
        -- "set temp max health bg opacity to 50" contains "max", which reads as
        -- the health-text mode, and this lane answered it with "I can show
        -- health text as max, but I need to know where" instead of letting the
        -- opacity control resolve.
        -- Any digit is enough: no slot mode is numeric, with or without a "to"
        -- connector ("change temp max health bg opacity 50").
        if tostring(text or ""):find("%d") then return nil end
        -- A mode word can also be part of a real control's name. "Show Power"
        -- is a per-frame boolean, so "i would like Focus Show Power off" names
        -- one control exactly and must not be answered with "which slot?".
        -- Router helpers are optional here: this file loads before the Router in
        -- some harnesses, so every call stays type-guarded.
        local Router = A and A.RouterPrivate
        if Router and type(Router.RequestNamesOneControl) == "function"
            and Router.RequestNamesOneControl(text)
        then
            return nil
        end
        -- This lane is about a TEXT SLOT, so the request has to be about text.
        -- "turn off show power" mentions no text or slot at all; the lane only
        -- claimed it by reading "off" as the slot mode None, and answered a
        -- per-frame boolean with "which slot?" instead of letting the ordinary
        -- ambiguity list offer the frames.
        if not ContainsAny(text, {
            "text", "slot", "left", "center", "centre", "right",
            "percent", "percentage", "number", "numbers", "value", "values",
        }) then
            return nil
        end
        local modeProbe = TextSlotSetting("unitframe", "player", tab, "center")
        local modeValue = modeProbe and A._TextSlotDropdownValueForText(modeProbe, text) or nil
        if modeValue == nil then return nil end
        local modeArea = tab == "power" and "power" or "health"
        local modeExample = tostring(DisplayValue(modeProbe, modeValue) or modeValue):lower()
        return {
            kind = "unknown",
            status = "failed",
            text = "I can show " .. modeArea .. " text as " .. modeExample
                .. ", but I need to know where. Each frame has a left, center, and right "
                .. modeArea .. " slot -- tell me the frame and the slot, for example 'set player "
                .. (tab == "power" and "power" or "hp") .. " right slot to " .. modeExample .. "'.",
            summary = "Asks which frame and text slot the requested mode applies to.",
        }
    end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #groups == 0 and #units == 0 then
        -- The text area, the slot and the value are all unambiguous here; only
        -- the frame is missing. Returning nil sent "put the health number in
        -- the middle" to the generic examples list, which never mentions this
        -- control. Ask for the one missing piece instead.
        local probe = TextSlotSetting("unitframe", "player", tab, slot)
        local probeValue = probe and A._TextSlotDropdownValueForText(probe, text) or nil
        if probeValue == nil then return nil end
        local areaWord = tab == "power" and "power" or "health"
        local exampleValue = tostring(DisplayValue(probe, probeValue) or probeValue):lower()
        return {
            kind = "unknown",
            status = "failed",
            text = "Which frame's " .. areaWord .. " text do you mean? Name the frame and I will set its "
                .. tostring(slot) .. " slot, for example 'set player " .. (tab == "power" and "power" or "hp")
                .. " " .. tostring(slot) .. " slot to " .. exampleValue .. "'.",
            summary = "Asks which frame owns the requested text slot.",
        }
    end

    local changes = {}
    local function AddTarget(frameType, unitOrScope)
        local setting = TextSlotSetting(frameType, unitOrScope, tab, slot)
        if not setting then return end
        local value = A._TextSlotDropdownValueForText(setting, text)
        if value == nil then return end
        changes[#changes + 1] = {
            setting = setting,
            value = value,
            valueLabel = DisplayValue(setting, value),
            textArea = tab,
            textSlot = slot,
        }
        -- Choosing slot content must not silently enable a hidden text area.
        -- Add the visibility write only when the user explicitly asks to
        -- show/enable it; this matches the multi-slot parser below.
        if value ~= "NONE" and A._HasTextSlotShowIntent(text) then
            A._AddTextSlotVisibilityChange(changes, frameType, unitOrScope, tab)
        end
    end

    for i = 1, #groups do
        AddTarget("group", A._TextGroupScopeName(groups[i]))
    end
    for i = 1, #units do
        AddTarget("unitframe", tostring(units[i]))
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text slot content",
        summary = "Changes the HP/Power left/center/right text slot for the selected unit or group.",
    }
end

local function HPTextSeparatorValueForText(setting, text)
    local symbols = { "-", "/", "\\", "|", "<", ">", "~", ":" }
    for i = 1, #symbols do
        local symbol = symbols[i]
        if text:find(symbol, 1, true) then
            if not setting or A._EnumAllowsValue(setting, symbol) then return symbol end
        end
    end
    if HasPhrase(text, "space") or HasPhrase(text, "blank") or HasPhrase(text, "none") or HasPhrase(text, "empty") then return "" end
    local value = EnumValueForText(setting, text)
    if value ~= nil and A._EnumAllowsValue(setting, value) then return value end
    return nil
end

function A._ParseHPTextOptionShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[78]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[79]) then return nil end
    if not ContainsAny(text, GeometryTextPhrases[80]) then return nil end

    local unitAttr
    local groupAttr
    local label
    local value
    local valueForSetting
    if ContainsAny(text, GeometryTextPhrases[81]) then
        unitAttr = "hpTextSeparator"
        groupAttr = "healthTextDelimiter"
        label = "HP Text Delimiter"
        valueForSetting = HPTextSeparatorValueForText
    elseif ContainsAny(text, GeometryTextPhrases[82]) then
        unitAttr = "hpTextReverse"
        groupAttr = "healthTextReverse"
        label = "Reverse HP Text"
        if DetectBoolean then value = DetectBoolean(text) end
        if value == nil then value = true end
    elseif ContainsAny(text, GeometryTextPhrases[83]) then
        unitAttr = "healthTextDecimals"
        groupAttr = "healthTextDecimals"
        label = "Health Text Decimals"
        if DetectBoolean then value = DetectBoolean(text) end
        if value == nil then value = true end
    else
        return nil
    end

    local units = DetectUnits(text)
    local groups = {}
    if #units == 0 then groups = DetectGroups(text) end
    if #units == 0 and #groups == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #units == 0 and #groups == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. unitAttr)
        local settingValue = value
        if valueForSetting then settingValue = valueForSetting(setting, text) end
        if setting and settingValue ~= nil then
            changes[#changes + 1] = { setting = setting, value = settingValue, valueLabel = DisplayValue(setting, settingValue) }
        end
    end
    for i = 1, #groups do
        local scope = A._TextGroupScopeName(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. "." .. groupAttr)
        local settingValue = value
        if valueForSetting then settingValue = valueForSetting(setting, text) end
        if setting and settingValue ~= nil then
            changes[#changes + 1] = { setting = setting, value = settingValue, valueLabel = DisplayValue(setting, settingValue) }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes an HP/Health text option for the selected frame scope.",
    }
end

function A._ParsePowerTextOptionShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[84]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[85]) then return nil end
    if not ContainsAny(text, GeometryTextPhrases[86]) then return nil end

    local units = DetectUnits(text)
    local groups = {}
    if #units == 0 then groups = DetectGroups(text) end
    if #units == 0 and #groups == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #units == 0 and #groups == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".powerTextSeparator")
        local settingValue = HPTextSeparatorValueForText(setting, text)
        if setting and settingValue ~= nil then
            changes[#changes + 1] = { setting = setting, value = settingValue, valueLabel = DisplayValue(setting, settingValue) }
        end
    end
    for i = 1, #groups do
        local scope = A._TextGroupScopeName(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".powerTextDelimiter")
        local settingValue = HPTextSeparatorValueForText(setting, text)
        if setting and settingValue ~= nil then
            changes[#changes + 1] = { setting = setting, value = settingValue, valueLabel = DisplayValue(setting, settingValue) }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Power Text Delimiter",
        bulkSafe = #changes > 1,
        summary = "Changes a Power/Mana text delimiter option for the selected frame scope.",
    }
end

function A._ParseTextAreaOffsetShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[87]) then return nil end
    if not ContainsAny(text, GeometryTextPhrases[88]) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then return nil end
    if ContainsAny(text, GeometryTextPhrases[89])
        or ContainsAny(text, GeometryTextPhrases[90])
    then
        return nil
    end

    local axis = A._DetailOffsetAxis and A._DetailOffsetAxis(text) or nil
    local direction
    if ContainsAny(text, GeometryTextPhrases[91]) then
        direction = "down"
    elseif ContainsAny(text, GeometryTextPhrases[92]) then
        direction = "up"
    else
        direction = DetectDirection(text, {})
    end
    if not axis and direction then
        axis = (direction == "left" or direction == "right") and "x" or "y"
    end
    if not axis then return nil end

    local value
    local relativeDelta
    if ContainsAny(text, GeometryTextPhrases[93]) and direction then
        relativeDelta = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then relativeDelta = -relativeDelta end
    else
        value = FirstNumber(text)
    end
    if value == nil and relativeDelta == nil then return nil end

    local units = DetectUnits(text)
    local groups = {}
    if #units == 0 then groups = DetectGroups(text) end
    if #units == 0 and #groups == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #units == 0 and #groups == 0 then return nil end

    local unitAttr = tab == "hp" and (axis == "x" and "hpOffsetX" or "hpOffsetY") or (axis == "x" and "powerOffsetX" or "powerOffsetY")
    -- Group registry keys use the DB field names (hpOffsetX/Y and
    -- powerOffsetX/Y); healthTextOffsetX/Y are semantic attributes only.
    local groupAttr = tab == "hp" and (axis == "x" and "hpOffsetX" or "hpOffsetY")
        or (axis == "x" and "powerOffsetX" or "powerOffsetY")
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. unitAttr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    for i = 1, #groups do
        local scope = A._TextGroupScopeName(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. "." .. groupAttr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = tab == "hp" and "Move HP text" or "Move Power text",
        bulkSafe = #changes > 1,
        summary = "Changes the whole HP/Power text offset for the selected frame scope.",
    }
end

function A._ParseTextSlotValueMoveShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[94]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[95]) then return nil end
    if not TextSlotMoveValueIntent(text) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if not slot then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #groups == 0 and #units == 0 then return nil end

    local function AddMoveTarget(out, frameType, unitOrScope)
        local dst = TextSlotSetting(frameType, unitOrScope, tab, slot)
        if not dst then return nil end
        local value, invalid = A._TextSlotDropdownValueForText(dst, text)
        if value == nil then return invalid end

        local valueLabel = DisplayValue(dst, value)
        out[#out + 1] = {
            setting = dst,
            value = value,
            textArea = tab,
            textSlot = A._TextSlotLower(slot),
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(dst, valueLabel, "Text slot") or (tostring(dst.label or "Text slot") .. ": " .. valueLabel),
            valueLabel = valueLabel,
        }

        if value ~= "NONE" then
            for _, sourceSlot in ipairs({ "Left", "Center", "Right" }) do
                if sourceSlot ~= slot then
                    local source = TextSlotSetting(frameType, unitOrScope, tab, sourceSlot)
                    if source and ReadSettingValue(source) == value then
                        local sourceValueLabel = DisplayValue(source, "NONE")
                        out[#out + 1] = {
                            setting = source,
                            value = "NONE",
                            textArea = tab,
                            textSlot = A._TextSlotLower(sourceSlot),
                            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(source, sourceValueLabel, "Text slot") or (tostring(source.label or "Text slot") .. ": " .. sourceValueLabel),
                            valueLabel = sourceValueLabel,
                        }
                    end
                end
            end
            A._AddTextSlotVisibilityChange(out, frameType, unitOrScope, tab)
        end
        return nil
    end

    local changes = {}
    local invalidValue
    for i = 1, #groups do
        invalidValue = AddMoveTarget(changes, "group", A._TextGroupScopeName(groups[i])) or invalidValue
    end
    for i = 1, #units do
        invalidValue = AddMoveTarget(changes, "unitframe", tostring(units[i])) or invalidValue
    end
    if #changes == 0 and invalidValue then
        return {
            kind = "unknown",
            text = "That value is not available for the selected text option.",
            status = "failed",
        }
    end
    if #changes == 0 then return nil end
    if #changes > 1 and (#groups + #units) > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching text-slot move targets",
            summary = "The request matched more than one text-slot target, so the Assistant is asking which real slot to change.",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Move text slot content",
        summary = "Moves a concrete HP/Power text value into the requested left/center/right text slot and clears the same value from its old slot.",
    }
end

function A._ParseTextSlotDropdownShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[96]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[97]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[98]) then return nil end
    if ContainsAny(text, GeometryTextPhrases[99]) then return nil end
    if not (text:find("text", 1, true) or text:find("slot", 1, true)
        or text:find("hp", 1, true) or text:find("health", 1, true)
        or text:find("power", 1, true) or text:find("mana", 1, true)
        or text:find("current", 1, true) or text:find("percent", 1, true)
        or text:find("%", 1, true) or text:find("it", 1, true)
        or text:find("that", 1, true) or text:find("this", 1, true)
        or text:find("same", 1, true) or text:find("now", 1, true)) then
        return nil
    end
    if not ContainsAny(text, GeometryTextPhrases[100]) then return nil end
    local tab = TextSelectorTab(text)
    local ctxFrame, ctxUnit, ctxTab, ctxSlot = A._SelectedTextTargetFromContext(tab)
    local contextReference = ContainsAny(text, GeometryTextPhrases[101])
    if not tab and contextReference then tab = ctxTab end
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if not slot then slot = A._BareTextSlotForValueText(text) end
    if ContainsAny(text, GeometryTextPhrases[102]) then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 and contextReference and ctxFrame and ctxUnit and ctxTab == tab then
        if ctxFrame == "group" then
            groups = { tostring(ctxUnit) }
        else
            units = { tostring(ctxUnit) }
        end
    end
    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #groups == 0 and #units == 0 and ctxFrame and ctxUnit and ctxTab == tab then
        if ctxFrame == "group" then
            groups = { tostring(ctxUnit) }
        else
            units = { tostring(ctxUnit) }
        end
    end

    local clearAllSlots = slot == nil
        and ContainsAny(text, GeometryTextPhrases[103])
        and not ContainsAny(text, GeometryTextPhrases[104])
    local ambiguousActiveSlots

    if not slot and contextReference then
        if #groups == 1 then
            slot = A._SelectedTextSlotFromContext("group", groups[1], tab)
        elseif #units == 1 then
            slot = A._SelectedTextSlotFromContext("unitframe", units[1], tab)
        end
        if not slot and ctxSlot and ctxTab == tab then slot = ctxSlot end
    end
    if not slot and not clearAllSlots then
        if #groups == 1 then
            slot = A._SelectedTextSlotFromContext("group", groups[1], tab)
        elseif #units == 1 then
            slot = A._SelectedTextSlotFromContext("unitframe", units[1], tab)
        end
    end
    if not slot and not clearAllSlots then
        local active
        if #groups == 1 then
            slot, active = InferSingleActiveTextSlot("group", groups[1], tab)
        elseif #units == 1 then
            slot, active = InferSingleActiveTextSlot("unitframe", units[1], tab)
        end
        if not slot and type(active) == "table" and #active > 1 then
            ambiguousActiveSlots = active
        end
    end
    if not slot and ctxSlot and ctxTab == tab and contextReference then slot = ctxSlot end

    local slots = {}
    if slot then
        slots[1] = slot
    elseif ambiguousActiveSlots and #ambiguousActiveSlots > 0 then
        slots = ambiguousActiveSlots
    else
        slots[1], slots[2], slots[3] = "Left", "Center", "Right"
    end

    local shouldShowTextArea = A._HasTextSlotShowIntent(text)
    local pendingVisibility = {}

    local function AddTextSlotChange(out, setting, slotName, frameType, unitOrScope)
        if not setting then return nil end
        local value, invalid = A._TextSlotDropdownValueForText(setting, text)
        if value ~= nil then
            local valueLabel = DisplayValue(setting, value)
            out[#out + 1] = {
                setting = setting,
                value = value,
                textArea = tab,
                textSlot = A._TextSlotLower(slotName),
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, valueLabel, "Text slot") or (tostring(setting.label or "Text slot") .. ": " .. valueLabel),
                valueLabel = valueLabel,
            }
            if shouldShowTextArea and value ~= "NONE" then
                pendingVisibility[#pendingVisibility + 1] = { frameType = frameType, unitOrScope = unitOrScope }
            end
        end
        return invalid
    end

    local changes = {}
    local invalidValue
    for i = 1, #groups do
        for j = 1, #slots do
            local keyName = A._TextSlotSettingKey(tab, slots[j])
            local setting = keyName and Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. keyName)
            invalidValue = AddTextSlotChange(changes, setting, slots[j], "group", groups[i]) or invalidValue
        end
    end
    for i = 1, #units do
        for j = 1, #slots do
            local keyName = A._TextSlotSettingKey(tab, slots[j])
            local setting = keyName and Registry and Registry:GetSetting(tostring(units[i]) .. "." .. keyName)
            invalidValue = AddTextSlotChange(changes, setting, slots[j], "unitframe", units[i]) or invalidValue
        end
    end
    if #changes == 0 and invalidValue then
        return {
            kind = "unknown",
            text = "That value is not available for the selected text option.",
            status = "failed",
        }
    end
    if #changes == 0 then return nil end
    if #changes > 1 and not clearAllSlots then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching text-slot options",
            summary = "The request did not identify one concrete text slot, so the Assistant is asking which real slot to change.",
        }
    end
    if #pendingVisibility > 0 then
        local seenVisibility = {}
        for i = 1, #pendingVisibility do
            local target = pendingVisibility[i]
            local id = tostring(target.frameType) .. ":" .. tostring(target.unitOrScope) .. ":" .. tostring(tab)
            if not seenVisibility[id] then
                seenVisibility[id] = true
                A._AddTextSlotVisibilityChange(changes, target.frameType, target.unitOrScope, tab)
            end
        end
    end
    local combinedTextValue = ContainsAny(text, GeometryTextPhrases[105])
    return {
        kind = "changes",
        changes = changes,
        label = "Set text slot content",
        summary = "Changes the HP/Power left/center/right text slot for the selected unit or group.",
        compoundComplete = combinedTextValue or nil,
    }
end

function A._ParseTextSlotOffsetShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryTextPhrases[106]) then return nil end
    if not ContainsAny(text, GeometryTextPhrases[107]) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if not slot then return nil end

    local axis = A._DetailOffsetAxis(text)
    local direction
    if ContainsAny(text, GeometryTextPhrases[108]) then
        direction = "down"
    elseif ContainsAny(text, GeometryTextPhrases[109]) then
        direction = "up"
    else
        direction = DetectDirection(text, {})
    end
    if (direction == "left" or direction == "right") and (slot == "Left" or slot == "Right")
        and not ContainsAny(text, GeometryTextPhrases[110])
    then
        return nil
    end
    if not axis and direction then
        axis = (direction == "left" or direction == "right") and "x" or "y"
    end
    if not axis then return nil end

    local value
    local relativeDelta
    if ContainsAny(text, GeometryTextPhrases[111]) and direction then
        relativeDelta = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then relativeDelta = -relativeDelta end
    else
        value = FirstNumber(text)
    end
    if value == nil and relativeDelta == nil then return nil end

    local prefix = (tab == "hp" and "hpText" or "powerText") .. slot
    local attr = prefix .. (axis == "x" and "OffsetX" or "OffsetY")
    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end

    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #groups > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching text-slot offset options",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text slot offset",
        summary = "Changes the HP/Power left/center/right text-slot offset for the selected unit or group.",
    }
end


P.TextSelectorTab = TextSelectorTab
P.TextSelectorSlot = TextSelectorSlot
P.TextSelectorIntent = TextSelectorIntent
