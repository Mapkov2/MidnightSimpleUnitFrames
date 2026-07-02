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
    if ContainsAny(text, { "advanced text tab", "advanced text", "text advanced", "text layers", "advanced tab" }) then return "advanced" end
    if ContainsAny(text, { "power text tab", "power text", "mana text", "power number", "power numbers", "mana number", "mana numbers", "power tab", "mana tab", "power", "mana" }) then return "power" end
    if ContainsAny(text, { "hp text tab", "health text tab", "hp text", "health text", "hp number", "hp numbers", "health number", "health numbers", "hp tab", "health tab", "hp", "health" }) then return "hp" end
    if ContainsAny(text, { "name text tab", "name text", "name tab", "name", "names" }) then return "name" end
    return nil
end

local function TextSelectorSlot(text)
    if ContainsAny(text, { "left slot", "slot left", "left text slot", "left anchor", "anchor left", "anchor to left", "to left", "on left", "on the left", "left side" })
        or (HasPhrase(text, "left") and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "align", "alignment" }))
    then
        return "left"
    end
    if ContainsAny(text, { "center slot", "centre slot", "middle slot", "slot center", "slot centre", "slot middle", "center text slot", "centre text slot", "middle text slot" })
        or ContainsAny(text, { "center anchor", "centre anchor", "middle anchor", "anchor center", "anchor centre", "anchor middle", "anchor to center", "anchor to centre", "anchor to middle", "to center", "to centre", "to middle", "in center", "in centre", "in middle", "in the center", "in the centre", "in the middle", "on center", "on centre", "on middle", "on the center", "on the centre", "on the middle", "center side", "centre side", "middle" })
        or ((HasPhrase(text, "center") or HasPhrase(text, "centre") or HasPhrase(text, "middle")) and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "align", "alignment" }))
    then
        return "center"
    end
    if ContainsAny(text, { "right slot", "slot right", "right text slot", "right anchor", "anchor right", "anchor to right", "to right", "on right", "on the right", "right side" })
        or (HasPhrase(text, "right") and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "align", "alignment" }))
    then
        return "right"
    end
    return nil
end

local function TextSelectorIntent(text, tab, slot)
    if tab == "name" and ContainsAny(text, { "anchor", "anchoring", "align", "alignment" }) then return false end
    if (tab == "hp" or tab == "power") and slot and ContainsAny(text, { "anchor", "anchoring", "align", "alignment" }) then return true end
    if ContainsAny(text, {
        "text area", "text tab", "text tabs", "text editor", "text slot", "slot selector", "slot dropdown",
        "selected slot", "left slot", "center slot", "centre slot", "right slot",
    }) then
        return true
    end
    return tab and ContainsAny(text, { "name text", "hp text", "health text", "power text", "mana text" }) and (HasPhrase(text, "tab") or slot ~= nil)
end

local function TextFontSizeIntent(text)
    if ContainsAny(text, {
        "font size", "text size", "name size", "name font size", "names size", "names font size",
        "hp font size", "health font size", "power font size", "mana font size",
        "hp text size", "health text size", "power text size", "mana text size",
        "hp number size", "hp numbers size", "health number size", "health numbers size",
        "power number size", "power numbers size", "mana number size", "mana numbers size",
        "text groesse", "name groesse", "name text groesse",
        "hp text groesse", "health text groesse", "power text groesse", "mana text groesse",
        "schriftgroesse", "schrift groesse",
    }) then
        return true
    end
    if not ContainsAny(text, {
        "bigger", "larger", "increase", "raise", "grow", "higher",
        "smaller", "decrease", "reduce", "lower", "shrink",
        "groesser", "kleiner", "erhoehe", "senke", "reduziere",
    }) then
        return false
    end
    return ContainsAny(text, {
        "name", "names", "name text", "hp text", "health text", "power text", "mana text",
        "hp number", "hp numbers", "health number", "health numbers",
        "power number", "power numbers", "mana number", "mana numbers",
    })
end

function A._ParseTextFontSizeShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff" }) then return nil end
    if ContainsAny(text, { "status icon", "status icons", "status indicator", "status indicators", "raid marker", "ready check", "leader icon", "assist icon" }) then return nil end
    if ContainsAny(text, {
        "layer", "text layer", "draw layer", "draw level", "level",
        "offset", "position", "pos", "x offset", "y offset",
        "move", "nudge", "shift", "anchor", "anchoring", "align", "alignment",
    }) then
        return nil
    end
    local allTextIntent = ContainsAny(text, {
        "all text", "all texts", "all frame text", "all unit text", "all unitframe text",
        "every text", "every text label", "all labels", "all numbers",
    }) and ContainsAny(text, {
        "font size", "text size", "bigger", "larger", "increase", "raise", "grow",
        "smaller", "decrease", "reduce", "lower", "shrink",
        "groesser", "kleiner", "erhoehe", "senke", "reduziere",
    })
    if not allTextIntent and not TextFontSizeIntent(text) then
        return nil
    end
    local tab = TextSelectorTab(text)
    local allText = tab == nil and allTextIntent
    if tab ~= "name" and tab ~= "hp" and tab ~= "power" and not allText then return nil end

    local attrs
    if allText then
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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff" }) then return nil end
    if ContainsAny(text, { "class power", "class resource", "class resources", "resource bar" }) then return nil end
    if not ContainsAny(text, { "text layer", "draw layer", "text level", "draw level", "layer" }) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "name" and tab ~= "hp" and tab ~= "power" then return nil end

    local relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
    if relativeDelta == nil then
        if ContainsAny(text, { "bring forward", "move forward", "raise forward", "forward", "front", "above", "up" }) then
            relativeDelta = 1
        elseif ContainsAny(text, { "send back", "move back", "backward", "behind", "below" }) then
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
        if ContainsAny(text, { "left hp text", "hp left text", "hp text left", "left health text", "health left text", "health text left", "left hp slot", "hp left slot", "hp slot left", "left health slot", "health left slot", "health slot left", "left hp label", "hp left label", "hp label left", "left health label", "health left label", "health label left" }) then return "Left" end
        if ContainsAny(text, { "center hp text", "centre hp text", "middle hp text", "hp center text", "hp centre text", "hp middle text", "hp text center", "hp text centre", "hp text middle", "center health text", "centre health text", "middle health text", "health center text", "health centre text", "health middle text", "health text center", "health text centre", "health text middle", "center hp slot", "centre hp slot", "middle hp slot", "hp center slot", "hp centre slot", "hp middle slot", "hp slot center", "hp slot centre", "hp slot middle", "center health slot", "centre health slot", "middle health slot", "health center slot", "health centre slot", "health middle slot", "health slot center", "health slot centre", "health slot middle", "center hp label", "centre hp label", "middle hp label", "hp center label", "hp centre label", "hp middle label", "hp label center", "hp label centre", "hp label middle", "center health label", "centre health label", "middle health label", "health center label", "health centre label", "health middle label", "health label center", "health label centre", "health label middle" }) then return "Center" end
        if ContainsAny(text, { "right hp text", "hp right text", "hp text right", "right health text", "health right text", "health text right", "right hp slot", "hp right slot", "hp slot right", "right health slot", "health right slot", "health slot right", "right hp label", "hp right label", "hp label right", "right health label", "health right label", "health label right" }) then return "Right" end
    else
        if ContainsAny(text, { "left power text", "power left text", "power text left", "left mana text", "mana left text", "mana text left", "left power slot", "power left slot", "power slot left", "left mana slot", "mana left slot", "mana slot left", "left power label", "power left label", "power label left", "left mana label", "mana left label", "mana label left" }) then return "Left" end
        if ContainsAny(text, { "center power text", "centre power text", "middle power text", "power center text", "power centre text", "power middle text", "power text center", "power text centre", "power text middle", "center mana text", "centre mana text", "middle mana text", "mana center text", "mana centre text", "mana middle text", "mana text center", "mana text centre", "mana text middle", "center power slot", "centre power slot", "middle power slot", "power center slot", "power centre slot", "power middle slot", "power slot center", "power slot centre", "power slot middle", "center mana slot", "centre mana slot", "middle mana slot", "mana center slot", "mana centre slot", "mana middle slot", "mana slot center", "mana slot centre", "mana slot middle", "center power label", "centre power label", "middle power label", "power center label", "power centre label", "power middle label", "power label center", "power label centre", "power label middle", "center mana label", "centre mana label", "middle mana label", "mana center label", "mana centre label", "mana middle label", "mana label center", "mana label centre", "mana label middle" }) then return "Center" end
        if ContainsAny(text, { "right power text", "power right text", "power text right", "right mana text", "mana right text", "mana text right", "right power slot", "power right slot", "power slot right", "right mana slot", "mana right slot", "mana slot right", "right power label", "power right label", "power label right", "right mana label", "mana right label", "mana label right" }) then return "Right" end
    end
    if ContainsAny(text, { "left of", "left side of", "to left of", "to the left of", "in left of", "in the left of" }) then return "Left" end
    if ContainsAny(text, { "center of", "centre of", "middle of", "center side of", "centre side of", "middle side of", "to center of", "to centre of", "to middle of", "to the center of", "to the centre of", "to the middle of", "in center of", "in centre of", "in middle of", "in the center of", "in the centre of", "in the middle of" }) then return "Center" end
    if ContainsAny(text, { "right of", "right side of", "to right of", "to the right of", "in right of", "in the right of" }) then return "Right" end
    local slot = TextSelectorSlot(text)
    if (slot == "left" or slot == "center" or slot == "right")
        and ContainsAny(text, {
            "slot", "text slot", "anchor", "anchoring", "side", "left side", "right side", "center side", "centre side", "middle side",
            "to left", "to right", "to center", "to centre", "to middle",
            "on left", "on the left", "on right", "on the right", "on center", "on centre", "on middle", "on the center", "on the centre", "on the middle",
            "in center", "in centre", "in middle", "in the center", "in the centre", "in the middle",
        })
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
    if ContainsAny(text, {
        "move", "nudge", "shift", "offset", "position", "pos", "x", "y", "up", "down",
        "layer", "size", "font size", "anchor", "anchoring", "align", "alignment",
    }) then
        return nil
    end
    local left = ContainsAny(text, { "left", "links" })
    local center = ContainsAny(text, { "center", "centre", "middle", "mitte" })
    local right = ContainsAny(text, { "right", "rechts" })
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
    if ContainsAny(text, {
        "castbar", "cast bar", "aura", "auras", "buff", "debuff",
        "class power", "class resource", "class resources", "resource bar",
        "power bar", "powerbar", "mana bar",
    }) then
        return nil
    end
    if ContainsAny(text, { "truncation", "truncate", "truncated", "clip", "clipping", "clip side", "ellipsis" }) then return nil end

    local tab = TextSelectorTab(text)
    if tab == "hp" or tab == "power" or tab == "advanced" then return nil end
    if ContainsAny(text, {
        "status", "status text", "status icon", "indicator", "icon",
        "raid marker", "ready check", "summon", "resurrect", "resurrection",
        "ghost", "dead", "afk", "dnd", "group number",
    }) and not ContainsAny(text, {
        "name", "name text", "unit name", "unitframe name", "unit frame name", "name label",
    }) then
        return nil
    end

    local value
    if ContainsAny(text, {
        "middle", "center", "centre", "centered", "centred",
        "to middle", "to the middle", "in middle", "in the middle",
        "to center", "to the center", "in center", "in the center",
        "to centre", "to the centre", "in centre", "in the centre",
    }) then
        value = "CENTER"
    elseif ContainsAny(text, {
        "to left", "to the left", "on left", "on the left", "left side",
        "anchor left", "left anchor", "anchor to left", "align left",
    }) or (HasPhrase(text, "left") and ContainsAny(text, { "anchor", "anchoring", "align", "alignment", "justify" })) then
        value = "LEFT"
    elseif ContainsAny(text, {
        "to right", "to the right", "on right", "on the right", "right side",
        "anchor right", "right anchor", "anchor to right", "align right",
    }) or (HasPhrase(text, "right") and ContainsAny(text, { "anchor", "anchoring", "align", "alignment", "justify" })) then
        value = "RIGHT"
    end
    if not value then return nil end

    local ctx = A.GetContext and A.GetContext() or nil
    local contextReference = ContainsAny(text, { "it", "that", "this", "selected", "same" })
    local explicitName = tab == "name" or ContainsAny(text, {
        "name", "name text", "unit name", "unitframe name", "unit frame name",
        "name label", "player name", "target name", "focus name", "pet name", "boss name",
    })
    local genericText = tab == nil
        and ContainsAny(text, { "text", "unit text", "unitframe text", "unit frame text", "frame text" })
        and ContainsAny(text, { "unitframe", "unit frame", "frame", "middle of", "center of", "centre of" })
    local placementIntent = ContainsAny(text, {
        "move", "put", "place", "set", "align", "anchor", "position",
        "center", "centre", "middle", "justify",
    })
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
        local showSetting = Registry and Registry:GetSetting(showKey)
        if showSetting and ReadSettingValue(showSetting) == false then
            changes[#changes + 1] = {
                setting = showSetting,
                value = true,
                valueLabel = "enabled",
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(showSetting, "enabled", "Name") or (tostring(showSetting.label or "Name") .. ": enabled"),
            }
        end
        local setting = Registry and Registry:GetSetting(settingKey)
        if setting and A._EnumAllowsValue(setting, value) then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                valueLabel = DisplayValue(setting, value),
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

function A._ParseNameTextOffsetShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, {
        "castbar", "cast bar", "aura", "auras", "buff", "debuff",
        "class power", "class resource", "class resources", "resource bar",
        "power bar", "powerbar", "mana bar", "hp text", "health text", "power text", "mana text",
    }) then
        return nil
    end
    if ContainsAny(text, {
        "raid group name", "raid group number", "group number", "pvp", "status icon",
        "status indicator", "ready check", "raid marker", "leader", "assist", "resurrect",
        "resurrection", "incoming rez", "summon",
    }) then
        return nil
    end
    if not ContainsAny(text, {
        "name", "name text", "unit name", "unitframe name", "unit frame name",
        "name label", "player name", "target name", "focus name", "pet name", "boss name",
        "party name", "raid name", "mythic raid name", "group name",
    }) then
        return nil
    end
    if not ContainsAny(text, { "offset", "position", "pos", "x", "y", "move", "nudge", "shift", "left", "right", "up", "down" }) then
        return nil
    end

    local axis = A._DetailOffsetAxis and A._DetailOffsetAxis(text) or nil
    local direction
    if ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" }) then
        direction = "down"
    elseif ContainsAny(text, { "up", "higher", "hoeher", "hoch", "oben" }) then
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
    if ContainsAny(text, { "move", "nudge", "shift" }) and direction then
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
    if ContainsAny(text, {
        "castbar", "cast bar", "aura", "auras", "buff", "debuff",
        "class power", "class resource", "class resources", "resource bar",
        "power bar", "powerbar", "mana bar",
    }) then
        return nil
    end
    if not ContainsAny(text, {
        "name", "name text", "unit name", "unitframe name", "unit frame name",
        "names", "name label", "player name", "target name", "focus name", "pet name", "boss name",
        "party name", "party names", "raid name", "raid names", "group name", "group names",
    }) then
        return nil
    end
    if not ContainsAny(text, { "put", "place", "set", "move", "position", "stick", "keep" }) then return nil end
    local verticalAnchorIntent = ContainsAny(text, { "anchor", "anchoring", "position" })
        and ContainsAny(text, { "top", "upper", "above", "over", "bottom", "lower", "below", "under" })
    if not verticalAnchorIntent and not ContainsAny(text, { "frame", "frames", "unitframe", "unit frame", "group frame", "group frames" }) then return nil end

    local direction
    if ContainsAny(text, { "above", "over", "top of", "on top of" })
        or (verticalAnchorIntent and ContainsAny(text, { "top", "upper" }))
    then
        direction = "up"
    elseif ContainsAny(text, { "below", "under", "bottom of", "underneath" })
        or (verticalAnchorIntent and ContainsAny(text, { "bottom", "lower" }))
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
        key = tostring(unitOrScope) .. "." .. (tab == "hp" and "showHP" or "showPower")
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
    return ContainsAny(text, {
        "move", "move the", "move max", "move current", "move percent",
        "relocate", "transfer", "send", "shift",
        "verschieben", "umsetzen",
    })
end

function A._ParseTextSlotDropdownValueShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power bar", "powerbar", "mana bar", "mana balken", "power balken" }) then return nil end
    if ContainsAny(text, {
        "move", "nudge", "shift", "offset", "position", "pos", "x", "y", "up", "down",
        "layer", "size", "font size", "anchor", "anchoring", "align", "alignment",
    }) then
        return nil
    end

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
        A._AddTextSlotVisibilityChange(changes, frameType, unitOrScope, tab)
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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power text", "mana text", "power bar", "powerbar", "mana bar" }) then return nil end
    if not ContainsAny(text, { "hp text", "health text", "health decimals", "hp decimals", "decimal percent", "reverse hp", "reverse health" }) then return nil end

    local unitAttr
    local groupAttr
    local label
    local value
    local valueForSetting
    if ContainsAny(text, { "delimiter", "separator", "seperator", "trennzeichen", "trenner" }) then
        unitAttr = "hpTextSeparator"
        groupAttr = "healthTextDelimiter"
        label = "HP Text Delimiter"
        valueForSetting = HPTextSeparatorValueForText
    elseif ContainsAny(text, {
        "reverse hp text", "hp text reverse", "reverse health text", "health text reverse",
        "reverse hp text order", "hp text reverse order", "reverse health text order", "health text reverse order",
    }) then
        unitAttr = "hpTextReverse"
        groupAttr = "healthTextReverse"
        label = "Reverse HP Text"
        value = DetectBoolean and DetectBoolean(text) or nil
        if value == nil then value = true end
    elseif ContainsAny(text, { "health text decimals", "hp text decimals", "health decimals", "hp decimals", "decimal percent" }) then
        unitAttr = "healthTextDecimals"
        groupAttr = "healthTextDecimals"
        label = "Health Text Decimals"
        value = DetectBoolean and DetectBoolean(text) or nil
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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power bar", "powerbar", "mana bar", "hp text", "health text" }) then return nil end
    if not ContainsAny(text, { "power text delimiter", "power text separator", "mana text delimiter", "mana text separator", "power delimiter", "mana delimiter" }) then return nil end

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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if not ContainsAny(text, { "offset", "position", "pos", "x", "y", "move", "nudge", "shift", "left", "right", "up", "down" }) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then return nil end
    if ContainsAny(text, { "slot", "left slot", "right slot", "center slot", "centre slot", "middle slot" })
        or ContainsAny(text, {
            "left hp text", "hp left text", "right hp text", "hp right text", "center hp text", "hp center text", "centre hp text", "hp centre text",
            "left health text", "health left text", "right health text", "health right text", "center health text", "health center text",
            "left power text", "power left text", "right power text", "power right text", "center power text", "power center text", "centre power text", "power centre text",
            "left mana text", "mana left text", "right mana text", "mana right text", "center mana text", "mana center text",
        })
    then
        return nil
    end

    local axis = A._DetailOffsetAxis and A._DetailOffsetAxis(text) or nil
    local direction
    if ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" }) then
        direction = "down"
    elseif ContainsAny(text, { "up", "higher", "hoeher", "hoch", "oben" }) then
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
    if ContainsAny(text, { "move", "nudge", "shift" }) and direction then
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
    local groupAttr = tab == "hp" and (axis == "x" and "healthTextOffsetX" or "healthTextOffsetY") or (axis == "x" and "powerTextOffsetX" or "powerTextOffsetY")
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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power bar", "powerbar", "mana bar", "mana balken", "power balken" }) then return nil end
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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power bar", "powerbar", "mana bar", "mana balken", "power balken" }) then return nil end
    if ContainsAny(text, { "dispel overlay", "debuff overlay", "current health only", "on current health only", "on health only" }) then return nil end
    if ContainsAny(text, { "dark mode", "dark bars", "dark bar", "bar color", "brightness" }) then return nil end
    if not (text:find("text", 1, true) or text:find("slot", 1, true)
        or text:find("hp", 1, true) or text:find("health", 1, true)
        or text:find("power", 1, true) or text:find("mana", 1, true)
        or text:find("current", 1, true) or text:find("percent", 1, true)
        or text:find("%", 1, true) or text:find("it", 1, true)
        or text:find("that", 1, true) or text:find("this", 1, true)
        or text:find("same", 1, true) or text:find("now", 1, true)) then
        return nil
    end
    if not ContainsAny(text, { "set", "show", "display", "use", "put", "make", "change", "hide", "turn off", "turn on", "create", "create new", "add", "new", "remove", "clear" }) then return nil end
    local tab = TextSelectorTab(text)
    local ctxFrame, ctxUnit, ctxTab, ctxSlot = A._SelectedTextTargetFromContext(tab)
    local contextReference = ContainsAny(text, { "it", "that", "this", "selected", "here", "there", "same", "now" })
    if not tab and contextReference then tab = ctxTab end
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if not slot then slot = A._BareTextSlotForValueText(text) end
    if ContainsAny(text, { "offset", "position", "pos", "x", "y", "up", "down", "move", "nudge", "shift", "layer", "size", "font size" }) then return nil end

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
        and ContainsAny(text, { "remove", "clear", "hide", "turn off", "disable", "empty", "none", "off" })
        and not ContainsAny(text, { "it", "that", "this", "selected", "here" })
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
    local combinedTextValue = ContainsAny(text, {
        "current and percent", "current and percentage", "current and max", "current and maximum",
        "max and percent", "maximum and percent", "max and percentage", "maximum and percentage",
    })
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
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "pos", "x", "y", "up", "down" }) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if not slot then return nil end

    local axis = A._DetailOffsetAxis(text)
    local direction
    if ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" }) then
        direction = "down"
    elseif ContainsAny(text, { "up", "higher", "hoeher", "hoch", "oben" }) then
        direction = "up"
    else
        direction = DetectDirection(text, {})
    end
    if (direction == "left" or direction == "right") and (slot == "Left" or slot == "Right")
        and not ContainsAny(text, {
            "left hp text", "hp left text", "left health text", "health left text", "left power text", "power left text", "left mana text", "mana left text",
            "right hp text", "hp right text", "right health text", "health right text", "right power text", "power right text", "right mana text", "mana right text",
            "left slot", "slot left", "right slot", "slot right", "left side", "right side", "left label", "right label",
        })
    then
        return nil
    end
    if not axis and direction then
        axis = (direction == "left" or direction == "right") and "x" or "y"
    end
    if not axis then return nil end

    local value
    local relativeDelta
    if ContainsAny(text, { "move", "nudge", "shift" }) and direction then
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
