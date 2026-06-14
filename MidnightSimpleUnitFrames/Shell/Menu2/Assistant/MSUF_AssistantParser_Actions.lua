--- Shell/Menu2/Assistant/MSUF_AssistantParser_Actions.lua
--- Action parser shard for concrete Assistant commands.
---
--- Returns action/changes plans rather than executing them, keeping undo,
--- confirmation, and combat gating in the downstream assistant runtime.

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
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local ALL_UNITFRAMES = P.ALL_UNITFRAMES
local PAGE_TEXT_TARGETS = P.PAGE_TEXT_TARGETS
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local TextMatchesAlias = P.TextMatchesAlias
local ExtractColor = P.ExtractColor
local DetectDirection = P.DetectDirection
local PageForText = P.PageForText
local WantsFullUnitCopy = P.WantsFullUnitCopy
local CopyScopesForText = P.CopyScopesForText
local WantsFullGroupCopy = P.WantsFullGroupCopy
local GroupCopyScopesForText = P.GroupCopyScopesForText

local COPY_VERBS = { "copy", "use", "kopiere", "kopieren", "uebernehme", "uebernehmen" }
local COPY_LIKE_TERMS = {
    "copy", "use", "kopiere", "kopieren", "uebernehme", "uebernehmen",
    "look like", "looks like", "same as", "the same as", "match", "mirror", "clone",
}

local function HasCopyIntent(text)
    return ContainsAny(text, COPY_LIKE_TERMS)
end

local function CopyCommandText(text)
    local normalized = Normalize(text)
    local padded = " " .. normalized .. " "
    local best
    for i = 1, #COPY_VERBS do
        local verb = COPY_VERBS[i]
        local startPos = padded:find(" " .. verb .. " ", 1, true)
        if startPos and (not best or startPos < best) then best = startPos end
    end
    if not best then return nil end
    return Trim(padded:sub(best + 1))
end

local function CopyTextParts(text)
    text = CopyCommandText(text)
    if not text then return nil, nil end
    local src, dst = text:match("^copy%s+.-%s+from%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+from%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+(.+)%s+over%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+(.+)%s+onto%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^use%s+.-%s+from%s+(.+)%s+for%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^use%s+(.+)%s+for%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopiere%s+.-%s+von%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopiere%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopieren%s+.-%s+von%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopieren%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehme%s+.-%s+von%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehme%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehmen%s+.-%s+von%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehmen%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    return nil, nil
end

local function LookLikeCopyTextParts(text)
    text = Normalize(text)
    local dst, src = text:match("^make%s+(.+)%s+look%s+like%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+look%s+the%s+same%s+as%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+the%s+same%s+as%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+match%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+mirror%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^match%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^mirror%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+look%s+like%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+look%s+the%s+same%s+as%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+match%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+mirror%s+(.+)$")
    if src and dst then return src, dst end
    return nil, nil
end

local function RemoveUnit(out, unit)
    if not unit then return out end
    local filtered = {}
    for i = 1, #(out or {}) do
        if out[i] ~= unit then filtered[#filtered + 1] = out[i] end
    end
    return filtered
end

local function CopyTargetsForText(text, source)
    if HasPhrase(text, "all") or HasPhrase(text, "all unitframes") or HasPhrase(text, "alle") or HasPhrase(text, "alle unitframes") then
        local targets = {}
        for i = 1, #ALL_UNITFRAMES do
            if ALL_UNITFRAMES[i] ~= source then targets[#targets + 1] = ALL_UNITFRAMES[i] end
        end
        return targets
    end
    return RemoveUnit(DetectUnits(text), source)
end

local function CopyGroupTargetsForText(text, source)
    if HasPhrase(text, "all") or HasPhrase(text, "all groups") or HasPhrase(text, "all group frames") or HasPhrase(text, "alle") or HasPhrase(text, "alle gruppenframes") then
        return RemoveUnit({ "party", "raid", "mythicraid" }, source)
    end
    return RemoveUnit(DetectGroups(text), source)
end

local function HasEnabledCopyScope(scopes)
    for _, value in pairs(scopes or {}) do
        if value == true then return true end
    end
    return false
end

local function ParseGroupCopy(text)
    if not HasCopyIntent(text) then return nil end
    local source, targets
    local srcText, dstText = CopyTextParts(text)
    if not (srcText and dstText) then
        srcText, dstText = LookLikeCopyTextParts(text)
    end
    if srcText and dstText then
        local srcGroups = DetectGroups(srcText)
        source = srcGroups[1]
        targets = CopyGroupTargetsForText(dstText, source)
    end
    if not source or not targets or #targets == 0 then
        local groups = DetectGroups(text)
        if #groups < 2 then
            if srcText and dstText then
                local srcUnits = DetectUnits(srcText)
                local srcGroups = DetectGroups(srcText)
                local dstUnits = DetectUnits(dstText)
                local dstGroups = DetectGroups(dstText)
                if (#srcUnits > 0 and #dstGroups > 0) or (#srcGroups > 0 and #dstUnits > 0) then return nil end
            end
            if ContainsAny(text, {
                "group setting", "group settings", "group frame setting", "group frame settings",
                "group frames", "group frame", "party setting", "party settings",
                "raid setting", "raid settings", "mythic raid setting", "mythic raid settings",
            }) then
                return {
                    kind = "answer",
                    status = "info",
                    text = "Tell me the source and target group frames. For example: copy party to raid, copy raid settings to party, or copy just health and text options from party to raid.",
                    summary = "Explains the missing source or target for a group-frame copy request.",
                }
            end
            return nil
        end
        source = groups[1]
        targets = {}
        for i = 2, #groups do targets[#targets + 1] = groups[i] end
    end
    local action = Registry and Registry:GetAction("copy_group")
    if not action then return nil end
    local confirm = (WantsFullGroupCopy and WantsFullGroupCopy(text)) or ContainsAny(text, { "all", "alle" }) or #targets > 1
    local scopes = GroupCopyScopesForText(text)
    if not HasEnabledCopyScope(scopes) then
        return {
            kind = "answer",
            status = "info",
            summary = "No group-frame copy categories selected.",
            text = "No group-frame copy categories were selected. Say exactly what to copy, for example 'copy raid auras to party' or 'copy raid layout without auras to party'.",
        }
    end
    return {
        kind = "action",
        action = action,
        args = { source = source, targets = targets, scopes = scopes },
        confirmRequired = confirm,
        label = "Copy " .. tostring((A.UnitLabels or {})[source] or source) .. " group settings",
        summary = "Copies via the existing group-frame copy helper.",
    }
end

local function ParseUnsupportedMixedCopy(text)
    if not HasCopyIntent(text) then return nil end
    local srcText, dstText = CopyTextParts(text)
    if not (srcText and dstText) then
        srcText, dstText = LookLikeCopyTextParts(text)
    end
    if not (srcText and dstText) then return nil end

    local srcUnits = DetectUnits(srcText)
    local srcGroups = DetectGroups(srcText)
    local dstUnits = DetectUnits(dstText)
    local dstGroups = DetectGroups(dstText)
    if #srcUnits > 0 and #dstGroups > 0 then
        return {
            kind = "answer",
            status = "info",
            text = "I can copy Unit Frame settings to other Unit Frames, and Group Frame settings to other Group Frames. I cannot safely copy a Unit Frame directly into a Group Frame because MSUF does not expose a shared public helper for that different DB shape. Try: copy just text options from target to player, or copy just health and text options from party to raid.",
            summary = "Explains unsupported mixed Unit/Group copy request without faking a helper.",
        }
    end
    if #srcGroups > 0 and #dstUnits > 0 then
        return {
            kind = "answer",
            status = "info",
            text = "I can copy Group Frame settings to other Group Frames, and Unit Frame settings to other Unit Frames. I cannot safely copy a Group Frame directly into a Unit Frame because MSUF does not expose a shared public helper for that different DB shape. Try: copy just health and text options from party to raid, or copy just text options from target to player.",
            summary = "Explains unsupported mixed Group/Unit copy request without faking a helper.",
        }
    end
    return nil
end

local function ParseCopy(text)
    if not HasCopyIntent(text) then return nil end
    local source, targets
    local srcText, dstText = CopyTextParts(text)
    if not (srcText and dstText) then
        srcText, dstText = LookLikeCopyTextParts(text)
    end
    if srcText and dstText then
        local srcUnits = DetectUnits(srcText)
        source = srcUnits[1]
        targets = CopyTargetsForText(dstText, source)
    end
    if not source or not targets or #targets == 0 then
        local units = DetectUnits(text)
        if #units < 2 then return nil end
        source = units[1]
        targets = {}
        for i = 2, #units do targets[#targets + 1] = units[i] end
    end
    local action = Registry and Registry:GetAction("copy_unit")
    if not action then return nil end
    local confirm = (WantsFullUnitCopy and WantsFullUnitCopy(text)) or ContainsAny(text, { "all", "alle" }) or #targets > 2
    return {
        kind = "action",
        action = action,
        args = { source = source, targets = targets, scopes = CopyScopesForText(text) },
        confirmRequired = confirm,
        label = "Copy " .. tostring((A.UnitLabels or {})[source] or source) .. " settings",
        summary = "Copies via the existing unit copy helper.",
    }
end

local function BuildContextReset(text, ctx)
    if not (ctx and type(ctx.lastUnit) == "string") then return nil end
    if not ContainsAny(text, { "reset", "restore", "zuruecksetzen", "default", "defaults" }) then return nil end
    if not (HasPhrase(text, "it") or HasPhrase(text, "that") or HasPhrase(text, "das")) then return nil end
    local setting = ctx.lastSetting and Registry:GetSetting(ctx.lastSetting) or nil
    local isPosition = setting and (setting.attribute == "offsetX" or setting.attribute == "offsetY")
    local action = Registry and Registry:GetAction(isPosition and "reset_unit_position" or "reset_unit_page")
    return action and {
        kind = "action",
        action = action,
        args = { unit = ctx.lastUnit },
        confirmRequired = not isPosition,
        label = isPosition and "Reset previous frame position" or "Reset previous frame settings",
        summary = "Uses the last Assistant unit as context.",
    } or nil
end

local GROUP_STATUS_ICON_ALIASES = {
    { key = "roleIcon", size = "roleIconSize", anchor = "roleIconAnchor", layer = "roleIconLayer", style = "roleIconStyle", aliases = { "role icon", "role icons", "role indicator", "role indicators", "role symbol", "role symbols" } },
    { key = "leaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", layer = "leaderIconLayer", style = "leaderIconStyle", aliases = { "leader icon", "leader icons", "leader indicator", "leader indicators", "leader symbol", "leader symbols" } },
    { key = "assistIcon", size = "assistIconSize", anchor = "assistIconAnchor", layer = "assistIconLayer", style = "assistIconStyle", aliases = { "assist icon", "assist icons", "assistant icon", "assistant icons", "assist indicator", "assist indicators", "assistant indicator", "assistant indicators", "assist symbol", "assist symbols", "assistant symbol", "assistant symbols" } },
    { key = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", layer = "raidMarkerLayer", aliases = { "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol", "target marker", "target marker icon", "target marker indicator", "target marker symbol" } },
    { key = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", layer = "readyCheckLayer", aliases = { "ready check", "ready check icon", "ready check indicator", "ready check symbol", "ready icon", "ready indicator", "ready symbol" } },
    { key = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", layer = "summonLayer", aliases = { "summon icon", "summon indicator", "summon symbol" } },
    { key = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", layer = "resurrectLayer", aliases = { "resurrect icon", "resurrect indicator", "resurrect symbol", "resurrection icon", "resurrection indicator", "resurrection symbol", "rez icon", "rez indicator", "rez symbol", "incoming resurrection", "incoming resurrection icon", "incoming resurrection indicator", "incoming resurrection symbol" } },
    { key = "pvpIcon", size = "pvpIconSize", anchor = "pvpIconAnchor", layer = "pvpIconLayer", aliases = { "pvp flag", "pvp icon", "pvp flag icon", "pvp indicator", "pvp flag indicator", "pvp status", "war mode indicator", "flagged indicator" } },
    { key = "phaseIcon", size = "phaseIconSize", anchor = "phaseAnchor", layer = "phaseLayer", aliases = { "phase icon", "phasing icon", "phase indicator", "phasing indicator", "phase symbol", "phasing symbol" } },
    { key = "statusText", size = "statusTextSize", anchor = "statusTextAnchor", layer = "statusTextLayer", aliases = { "dead text", "dead status text", "status text" } },
    { key = "statusGhostText", size = "statusGhostTextSize", anchor = "statusGhostTextAnchor", layer = "statusGhostTextLayer", aliases = { "ghost text", "ghost status text" } },
    { key = "statusAFKText", size = "statusAFKTextSize", anchor = "statusAFKTextAnchor", layer = "statusAFKTextLayer", aliases = { "afk text", "dnd text", "afk dnd text", "away text" } },
}

local GROUP_STATUS_ICON_PACK_ALIASES = {
    inherit = "DEFAULT",
    global = "DEFAULT",
    default = "DEFAULT",
    ["follow global"] = "DEFAULT",
    blizzard = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
}

local function GroupStatusIconForText(text)
    for i = 1, #GROUP_STATUS_ICON_ALIASES do
        local row = GROUP_STATUS_ICON_ALIASES[i]
        if ContainsAny(text, row.aliases) then return row.key end
    end
    return nil
end

local function HasGroupStatusScopeIntent(text)
    if #DetectGroups(text) > 0 then return true end
    if ContainsAny(text, {
        "group", "groups", "group frame", "group frames", "group status", "group icon", "group icons",
        "party", "party frame", "party frames", "raid", "raid frame", "raid frames", "mythic raid",
    }) then return true end
    local icon = GroupStatusIconForText(text)
    return icon == "readyCheckIcon" or icon == "summonIcon" or icon == "phaseIcon"
end

local function GroupStatusIconSpecForText(text)
    local key = GroupStatusIconForText(text)
    if not key then return nil end
    for i = 1, #GROUP_STATUS_ICON_ALIASES do
        if GROUP_STATUS_ICON_ALIASES[i].key == key then return GROUP_STATUS_ICON_ALIASES[i] end
    end
    return nil
end

local GROUP_STATUS_ICON_TERMS = {
    "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators", "symbol", "symbols",
    "role icon", "role icons", "leader icon", "leader icons", "assist icon", "assist icons",
    "raid marker", "raid markers", "ready check", "ready icon", "summon", "summon icon",
    "resurrect", "resurrect icon", "resurrection", "resurrection icon", "incoming resurrection",
    "incoming resurrection icon", "incoming rez", "incoming rez icon", "rez icon",
    "pvp flag", "pvp icon", "pvp indicator", "phase icon", "dead text", "ghost text", "afk text", "dnd text",
}

local GROUP_STATUS_MIDNIGHT_STYLE_TERMS = {
    "midnight style", "use midnight style", "midnight icon style", "midnight icons",
    "midnight status icons", "status icon midnight style", "status icons midnight style",
}

local function FirstGroupOrDefault(text)
    local groups = DetectGroups(text)
    return groups[1] or "party"
end

local function AliasValueForText(text, aliases, values)
    local compactText = Compact(text)
    if type(aliases) == "table" then
        local bestValue, bestLen
        for alias, value in pairs(aliases) do
            local compactAlias = Compact(alias)
            if HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true)) then
                local len = #compactAlias
                if not bestLen or len > bestLen then bestValue, bestLen = value, len end
            end
        end
        if bestValue ~= nil then return bestValue end
    end
    for i = 1, #(values or {}) do
        local value = values[i]
        local compactValue = Compact(value)
        if HasPhrase(text, tostring(value)) or (#compactValue >= 5 and compactText:find(compactValue, 1, true)) then return value end
    end
    return nil
end

local GROUP_SPELL_PLACED_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", icon = "icon", square = "square", dot = "square", bar = "bar", number = "number", text = "number" }
local GROUP_SPELL_FRAME_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", healthtint = "healthtint", ["health tint"] = "healthtint", tint = "healthtint", border = "border", outline = "border", glow = "glow", pulse = "pulse", namecolor = "namecolor", ["name color"] = "namecolor" }
local GROUP_SPELL_GROWTH_ALIASES = { rightdown = "RIGHTDOWN", ["right down"] = "RIGHTDOWN", ["right then down"] = "RIGHTDOWN", leftdown = "LEFTDOWN", ["left down"] = "LEFTDOWN", ["left then down"] = "LEFTDOWN", rightup = "RIGHTUP", ["right up"] = "RIGHTUP", ["right then up"] = "RIGHTUP", leftup = "LEFTUP", ["left up"] = "LEFTUP", ["left then up"] = "LEFTUP" }
local GROUP_SPELL_ANCHOR_ALIASES = { topleft = "TOPLEFT", ["top left"] = "TOPLEFT", topright = "TOPRIGHT", ["top right"] = "TOPRIGHT", bottomleft = "BOTTOMLEFT", ["bottom left"] = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT", ["bottom right"] = "BOTTOMRIGHT", center = "CENTER", centre = "CENTER", middle = "CENTER", top = "TOP", bottom = "BOTTOM", left = "LEFT", right = "RIGHT" }

local function StatusAnchorIntent(text)
    if ContainsAny(text, { "anchor", "anchor point", "anchor position", "position dropdown" }) then return true end
    if ContainsAny(text, {
        "to top", "to the top", "to bottom", "to the bottom", "to left", "to the left", "to right", "to the right",
        "on top", "on the top", "on bottom", "on the bottom", "on left", "on the left", "on right", "on the right",
        "top left", "top right", "bottom left", "bottom right", "upper left", "upper right", "lower left", "lower right",
        "above frame", "above the frame", "over frame", "over the frame", "below frame", "below the frame", "under frame", "under the frame",
        "left side", "right side", "right of name", "left of name", "right to name", "left to name",
    }) and ContainsAny(text, { "put", "place", "set", "move", "position", "stick", "keep" }) then
        return true
    end
    if ContainsAny(text, { "above", "over", "below", "under" })
        and ContainsAny(text, { "frame", "frames", "unitframe", "unit frame", "group frame", "group frames" })
        and ContainsAny(text, { "put", "place", "set", "move", "position", "stick", "keep" })
    then
        return true
    end
    return false
end

local function StatusAnchorValueForText(text, aliases, values)
    if not StatusAnchorIntent(text) then return nil end
    if ContainsAny(text, { "above frame", "above the frame", "over frame", "over the frame" })
        or (ContainsAny(text, { "above", "over" }) and ContainsAny(text, { "frame", "frames", "unitframe", "unit frame", "group frame", "group frames" }))
    then
        return AliasValueForText("top", aliases, values) or AliasValueForText("top left", aliases, values)
    end
    if ContainsAny(text, { "below frame", "below the frame", "under frame", "under the frame" })
        or (ContainsAny(text, { "below", "under" }) and ContainsAny(text, { "frame", "frames", "unitframe", "unit frame", "group frame", "group frames" }))
    then
        return AliasValueForText("bottom", aliases, values) or AliasValueForText("bottom left", aliases, values)
    end
    return AliasValueForText(text, aliases, values)
end

local function ParseGroupSpellIndicatorAction(text, raw)
    if not ContainsAny(text, { "spell indicator", "spell indicators", "tracked spell", "tracked spells" }) then return nil end
    local scope = FirstGroupOrDefault(text)
    local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(text) or nil

    if ContainsAny(text, { "multi spec", "multispec", "track selected multi spec", "track spec" }) and spec and spec ~= "auto" and spec ~= "multi" then
        local action = Registry and Registry:GetAction("set_group_spell_indicator_multi_spec")
        local value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, { "remove", "clear", "stop" }) end
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, value = value },
            label = "Set group spell indicator multi-spec",
            summary = "Toggles a concrete spec entry in Spell Indicators Multi-Spec mode.",
        } or nil
    end

    local aura, resolvedSpec
    if type(A.ResolveGroupSpellAura) == "function" then
        aura, resolvedSpec = A.ResolveGroupSpellAura(spec, text)
    end
    spec = spec or resolvedSpec
    if ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then
        local action = Registry and Registry:GetAction("reset_group_spell_indicator_aura")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, aura = aura or text },
            label = "Reset group spell indicator aura",
            summary = "Resets one tracked spell indicator entry to its defaults.",
        } or nil
    end

    if ContainsAny(text, { "move", "order", "reorder", "first", "last", "slot", "position" }) and aura then
        local action = Registry and Registry:GetAction("move_group_spell_indicator_order")
        local position = FirstNumber(text)
        if ContainsAny(text, { "first", "top", "front" }) then position = 1 end
        if ContainsAny(text, { "last", "bottom", "end" }) then position = 999 end
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, aura = text, position = position or 1 },
            label = "Move group spell indicator order",
            summary = "Changes the tracked spell display order.",
        } or nil
    end

    local field, value
    if ContainsAny(text, { "only my cast", "only mine", "own cast", "cast by me" }) then
        field, value = "onlyOwn", DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, { "cooldown text size", "cooldown font size" }) then
        field, value = "placedCooldownSize", FirstNumber(text)
    elseif ContainsAny(text, { "cooldown swipe" }) then
        field, value = "placedCooldownSwipe", DetectBoolean(text)
    elseif ContainsAny(text, { "cooldown text", "show cooldown" }) then
        field, value = "placedCooldown", DetectBoolean(text)
    elseif ContainsAny(text, { "show when missing", "when missing", "missing indicator" }) then
        field, value = "placedMissing", DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, { "bar width" }) then
        field, value = "placedBarWidth", FirstNumber(text)
    elseif ContainsAny(text, { "growth", "grow" }) then
        field, value = "placedGrowth", AliasValueForText(text, GROUP_SPELL_GROWTH_ALIASES, { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" })
    elseif ContainsAny(text, { "frame color", "effect color", "tint color", "glow color", "border color" }) then
        local r, g, b, label = ExtractColor(raw, text)
        if r then field, value = "frameColor", { r = r, g = g, b = b, label = label } end
    elseif ContainsAny(text, { "frame effect", "effect type", "frame type" }) then
        field, value = "frameType", AliasValueForText(text, GROUP_SPELL_FRAME_ALIASES, { "none", "healthtint", "border", "glow", "pulse", "namecolor" })
    elseif ContainsAny(text, { "frame priority", "effect priority", "priority" }) then
        field, value = "framePriority", FirstNumber(text)
    elseif ContainsAny(text, { "tint alpha", "frame alpha", "effect alpha" }) then
        field, value = "frameAlpha", FirstNumber(text)
        if value and value > 1 then value = value / 100 end
    elseif ContainsAny(text, { "thickness", "border thickness", "glow thickness" }) then
        field, value = "frameThickness", FirstNumber(text)
    elseif ContainsAny(text, { "indicator type", "placed indicator", "placed type", "type" }) then
        field, value = "placedType", AliasValueForText(text, GROUP_SPELL_PLACED_ALIASES, { "none", "icon", "square", "bar", "number" })
    elseif ContainsAny(text, { "anchor", "position" }) then
        field, value = "placedAnchor", AliasValueForText(text, GROUP_SPELL_ANCHOR_ALIASES, { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" })
    elseif ContainsAny(text, { "x offset", "x position", "x" }) then
        field, value = "placedX", FirstNumber(text)
    elseif ContainsAny(text, { "y offset", "y position", "y" }) then
        field, value = "placedY", FirstNumber(text)
    elseif ContainsAny(text, { "size", "icon size" }) then
        field, value = "placedSize", FirstNumber(text)
    else
        value = DetectBoolean(text)
        if value ~= nil then field = "enabled" end
    end

    if not (field and value ~= nil and aura) then return nil end
    local action = Registry and Registry:GetAction("set_group_spell_indicator_aura")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, spec = spec, aura = text, field = field, value = value },
        label = "Set group spell indicator",
        summary = "Configures one tracked spell indicator entry.",
    } or nil
end

local function ParseGroupCornerIndicatorReset(text)
    if not ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "corner indicator", "corner indicators", "corner dot", "corner dots", "custom spell" }) then return nil end
    local scope = FirstGroupOrDefault(text)
    local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
    if slot then
        local action = Registry and Registry:GetAction("reset_group_corner_indicator_slot")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, slot = text },
            label = "Reset group corner indicator slot",
            summary = "Resets one corner indicator slot and clears its custom spell editor state.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_group_corner_indicators")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset group corner indicators",
        summary = "Resets all corner indicator slots for the selected group scope.",
    } or nil
end

local function ParseGroupStatusIconReset(text)
    if not ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, GROUP_STATUS_ICON_TERMS) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then return nil end
    if #explicitGroups == 0 and not HasGroupStatusScopeIntent(text) then return nil end
    if #explicitGroups == 0 and ContainsAny(text, { "selected status indicator", "selected status icon", "current status indicator", "current status icon", "unit status indicator", "unit status icon" }) then return nil end
    local scope = FirstGroupOrDefault(text)
    local icon = GroupStatusIconForText(text)
    if icon then
        local action = Registry and Registry:GetAction("reset_group_status_icon")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, icon = icon },
            label = "Reset group status icon",
            summary = "Resets placement and icon pack for one group status icon.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_group_status_icons")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset group status icons",
        summary = "Resets placement and icon packs for all group status icons in the selected scope.",
    } or nil
end

local function ParseGroupStatusPreview(text)
    if not ContainsAny(text, { "preview", "show all", "current indicator", "all indicators", "all status icons", "test", "test mode", "preview mode" }) then return nil end
    if not ContainsAny(text, GROUP_STATUS_ICON_TERMS) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then return nil end
    if #explicitGroups == 0 and not HasGroupStatusScopeIntent(text) then return nil end
    if #explicitGroups == 0 and ContainsAny(text, { "selected status indicator", "selected status icon", "current status indicator", "current status icon", "unit status indicator", "unit status icon" }) then return nil end
    local scope = FirstGroupOrDefault(text)
    local icon = GroupStatusIconForText(text)
    local mode = ContainsAny(text, { "show all", "all indicators", "all status icons", "preview all" }) and "all" or "current"
    local action = Registry and Registry:GetAction("preview_group_status_icon")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, icon = icon, mode = mode, text = text },
        label = mode == "all" and "Show all group status icons" or "Preview group status icon",
        summary = "Controls the group-frame status icon preview mode.",
    } or nil
end

local function RelativeLayerDeltaForText(text)
    local amount = FirstNumber(text) or 1
    if ContainsAny(text, { "behind", "backward", "backwards", "send back", "to back", "lower layer", "lower draw", "hinter", "nach hinten" }) then
        return -amount
    end
    if ContainsAny(text, { "forward", "front", "to front", "bring forward", "higher layer", "higher draw", "nach vorne" }) then
        return amount
    end
    return nil
end

local function GroupStatusScopesForText(text)
    local scopes = {}
    if ContainsAny(text, { "all group frames", "all groups", "every group frame", "each group frame", "for all group frames", "alle gruppen", "alle gruppenframes" }) then
        scopes[1], scopes[2], scopes[3] = "party", "raid", "mythicraid"
        return scopes
    end
    local groups = DetectGroups(text)
    if #groups > 0 then return groups end
    scopes[1] = FirstGroupOrDefault(text)
    return scopes
end

local function BuildGroupStatusChanges(scopes, dbKey, value, relativeDelta)
    local changes = {}
    for i = 1, #(scopes or {}) do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. "." .. tostring(dbKey or ""))
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    return changes
end

local RAID_MARKER_SYMBOL_WORDS = {
    "star", "circle", "diamond", "triangle", "moon", "square", "cross", "x", "skull",
    "raid star", "raid circle", "raid diamond", "raid triangle", "raid moon", "raid square", "raid cross", "raid skull",
}

local function HasStatusOffsetIntent(text)
    return ContainsAny(text, { "x offset", "offset x", "horizontal offset", "y offset", "offset y", "vertical offset" })
end

local function RaidMarkerSymbolAnswer()
    return {
        kind = "answer",
        status = "info",
        text = "Raid Marker shows the actual WoW raid target marker. MSUF can show, hide, move, resize, anchor, and layer that indicator, but choosing Star/Circle/Skull is done on the unit in WoW.",
        summary = "Explains why raid-marker symbol words are not a real MSUF setting.",
    }
end

local function ParseGroupStatusIconDetail(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    local hasGroupStatus = ContainsAny(text, GROUP_STATUS_ICON_TERMS)
    if not hasGroupStatus and not ContainsAny(text, GROUP_STATUS_MIDNIGHT_STYLE_TERMS) then return nil end

    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then return nil end
    if ContainsAny(text, { "preview", "test", "test mode", "preview mode" })
        and not ContainsAny(text, { "turn on", "turn off", "enable", "disable", "hide", "show midnight", "classic style", "midnight style" })
    then
        return nil
    end

    local scopes = GroupStatusScopesForText(text)
    if ContainsAny(text, GROUP_STATUS_MIDNIGHT_STYLE_TERMS) then
        local value = DetectBoolean(text)
        if value == nil then
            if ContainsAny(text, { "classic style", "classic icons", "classic status icons" }) then
                value = false
            elseif ContainsAny(text, { "midnight style", "midnight icons", "midnight status icons" }) then
                value = true
            end
        end
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, "useMidnightIcons", value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icons Use Midnight Style",
                    bulkSafe = #changes > 1,
                    summary = "Changes the group-frame Midnight status icon style without changing individual icon visibility.",
                }
            end
        end
    end

    local iconSpec = GroupStatusIconSpecForText(text)
    if not iconSpec then return nil end
    if iconSpec.key == "raidMarker" and ContainsAny(text, RAID_MARKER_SYMBOL_WORDS) and not HasStatusOffsetIntent(text) then
        return RaidMarkerSymbolAnswer()
    end
    local anchorIntent = StatusAnchorIntent(text)

    local enabledKey = iconSpec.enabled or iconSpec.key
    if enabledKey and not anchorIntent then
        local value = DetectBoolean(text)
        if value == nil then
            if ContainsAny(text, { "hide", "disable", "disabled", "turn off", "off", "remove" }) then
                value = false
            elseif ContainsAny(text, { "show", "enable", "enabled", "turn on", "on", "display" }) then
                value = true
            end
        end
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, enabledKey, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Visibility",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon visibility toggle.",
                }
            end
        end
    end

    if ContainsAny(text, { "icon pack", "icon style" }) and iconSpec.style then
        local value = AliasValueForText(text, GROUP_STATUS_ICON_PACK_ALIASES, { "DEFAULT", "BLIZZARD", "CLASSIC", "MIDNIGHT" })
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.style, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Pack",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon pack/style dropdown.",
                }
            end
        end
    end

    if anchorIntent and iconSpec.anchor then
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[1] or "") .. "." .. tostring(iconSpec.anchor))
        local value = setting and StatusAnchorValueForText(text, GROUP_SPELL_ANCHOR_ALIASES, setting.values or { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" })
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.anchor, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Anchor",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon anchor dropdown.",
                }
            end
        end
    end

    if ContainsAny(text, { "layer", "draw layer", "draw order", "behind", "forward", "front", "backward", "backwards" }) then
        local relativeDelta = RelativeLayerDeltaForText(text)
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if value ~= nil or relativeDelta ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.layer, value, relativeDelta)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Layer",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon layer slider.",
                }
            end
        end
    end

    if ContainsAny(text, { "size", "icon size", "indicator size", "symbol size", "scale", "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink", "groesser", "kleiner" }) then
        if ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "verschiebe" }) and DetectDirection(text) then return nil end
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[1] or "") .. "." .. tostring(iconSpec.size))
        local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text, 1) or nil
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if value ~= nil or relativeDelta ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.size, value, relativeDelta)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Size",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon size slider.",
                }
            end
        end
    end

    return nil
end

local UNIT_STATUS_RESET_TERMS = {
    "status indicator", "status indicators", "status icon", "status icons", "status symbol", "status symbols", "indicator position", "level indicator", "level text",
    "leader icon", "leader indicator", "leader symbol", "assist icon", "assist indicator", "assist symbol",
    "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol", "raid icon", "raid indicator", "raid symbol", "raid group", "raid group name",
    "elite icon", "elite indicator", "elite symbol", "rare icon", "rare indicator", "rare symbol",
    "dead text", "status text", "combat indicator", "combat icon", "combat symbol", "combat state symbol",
    "rested indicator", "resting indicator", "rested icon", "resting icon", "rested symbol", "resting symbol",
    "incoming rez", "incoming rez indicator", "incoming rez symbol", "incoming resurrection", "incoming resurrection indicator", "incoming resurrection symbol",
    "resurrection icon", "resurrection indicator", "resurrection symbol",
    "pvp flag", "pvp indicator", "pvp icon", "pvp flag indicator", "pvp flag icon", "pvp status", "war mode indicator",
}

local UNIT_STATUS_RUNTIME_TEXT_TERMS = {
    "afk text", "afk indicator", "afk status", "afk status text", "afk status indicator",
    "dnd text", "dnd indicator", "dnd status", "dnd status text", "dnd status indicator",
    "away text", "away indicator", "away status", "afk dnd text", "afk dnd indicator",
}

local UNIT_STATUS_SIZE_TERMS = {
    "size", "font size", "text size", "icon size", "indicator size", "symbol size", "scale",
    "bigger", "larger", "smaller", "increase", "decrease", "reduce", "raise", "lower", "grow", "shrink",
    "groesse", "groesser", "kleiner", "erhoehe", "erhoehen", "reduziere", "verringere",
}

local UNIT_STATUS_MIDNIGHT_STYLE_TERMS = {
    "midnight style", "use midnight style", "midnight icon style", "midnight icons",
    "midnight status style", "midnight status icon", "midnight status icons",
    "status icon midnight style", "status icons midnight style",
    "status indicator midnight style", "status indicators midnight style",
    "classic style", "use classic style", "classic icon style", "classic icons",
    "classic status style", "classic status icon", "classic status icons",
    "status icon classic style", "status icons classic style",
    "status indicator classic style", "status indicators classic style",
}

local UNIT_STATUS_ICON_PACK_ALIASES = {
    blizzard = "BLIZZARD",
    default = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
}

local UNIT_STATUS_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    upperleft = "TOPLEFT",
    ["upper left"] = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    upperright = "TOPRIGHT",
    ["upper right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    lowerleft = "BOTTOMLEFT",
    ["lower left"] = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    lowerright = "BOTTOMRIGHT",
    ["lower right"] = "BOTTOMRIGHT",
    center = "CENTER",
    centre = "CENTER",
    middle = "CENTER",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
    nameright = "NAMERIGHT",
    ["name right"] = "NAMERIGHT",
    ["right of name"] = "NAMERIGHT",
    ["right to name"] = "NAMERIGHT",
    nameleft = "NAMELEFT",
    ["name left"] = "NAMELEFT",
    ["left of name"] = "NAMELEFT",
    ["left to name"] = "NAMELEFT",
}

local function UnitStatusHasIntent(text)
    return ContainsAny(text, UNIT_STATUS_RESET_TERMS) or ContainsAny(text, UNIT_STATUS_RUNTIME_TEXT_TERMS)
end

local function ResolveUnitStatusSpecForText(unit, text)
    local resolver = A.ResolveUnitStatusSpec
    local spec = resolver and resolver(unit, text) or nil
    if spec then return spec end
    if ContainsAny(text, UNIT_STATUS_RUNTIME_TEXT_TERMS) then
        return resolver and resolver(unit, "status text") or nil
    end
    return nil
end

local function UnitStatusUnitsOrCurrent(text)
    local units = DetectUnits(text)
    if #units == 0 then
        local currentPageUnit = P.CurrentPageUnit
        local currentUnit = type(currentPageUnit) == "function" and currentPageUnit() or nil
        if currentUnit then units = { currentUnit } end
    end
    return units
end

local function CurrentUnitStatusValue(unit)
    local selection = M and M.unitStatusSelection
    if type(selection) == "table" and type(selection[unit]) == "string" and selection[unit] ~= "" then
        return selection[unit]
    end
    return nil
end

local function ResolveUnitStatusSpecOrSelected(unit, text)
    local spec = ResolveUnitStatusSpecForText(unit, text)
    if spec then return spec end
    if ContainsAny(text, { "selected status indicator", "selected status icon", "current status indicator", "current status icon" }) then
        local selected = CurrentUnitStatusValue(unit)
        if selected then return ResolveUnitStatusSpecForText(unit, selected) end
    end
    return nil
end

local function UnitStatusNeedsUnitContext(text)
    return ContainsAny(text, {
        "selected status indicator", "selected status icon", "current status indicator", "current status icon",
        "unit status indicator", "unit status icon", "status indicator", "status icon",
    })
end

local function ParseUnitStatusIndicatorReset(text, ctx)
    if not ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not UnitStatusHasIntent(text) then return nil end
    local units = UnitStatusUnitsOrCurrent(text)
    if #units == 0 and ctx and ctx.lastUnit then units = { ctx.lastUnit } end
    local action = Registry and Registry:GetAction("reset_unit_status_indicator")
    if #units == 0 and UnitStatusNeedsUnitContext(text) then
        return action and {
            kind = "action",
            action = action,
            args = { text = text },
            label = "Reset unit status indicator",
            summary = "Needs a unit frame or selected status indicator before resetting placement and style fields.",
        } or nil
    end
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = ResolveUnitStatusSpecOrSelected(unit, text)
    if not spec and UnitStatusNeedsUnitContext(text) then
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit, text = text },
            label = "Reset unit status indicator",
            summary = "Needs a selected status indicator before resetting placement and style fields.",
        } or nil
    end
    if not spec then return nil end
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit, status = spec.value, text = text },
        label = "Reset " .. tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "status indicator"),
        summary = "Resets placement and style fields for one unit-frame status indicator.",
    } or nil
end

local function ParseUnitStatusPreview(text, ctx)
    if not ContainsAny(text, { "preview", "show all", "current indicator", "all indicators", "all status icons" }) then return nil end
    if not UnitStatusHasIntent(text) then return nil end
    local units = UnitStatusUnitsOrCurrent(text)
    local unit = units[1] or (ctx and ctx.lastUnit) or "player"
    local spec = ResolveUnitStatusSpecOrSelected(unit, text)
    local mode = ContainsAny(text, { "show all", "all indicators", "all status icons", "preview all" }) and "all" or "current"
    local action = Registry and Registry:GetAction("preview_unit_status_indicator")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit, status = spec and spec.value, mode = mode, text = text },
        label = mode == "all" and "Show all status indicators" or "Preview status indicator",
        summary = "Controls the unit-frame status indicator preview mode.",
    } or nil
end

local function ParseUnitStatusIconStyle(text)
    if not ContainsAny(text, UNIT_STATUS_MIDNIGHT_STYLE_TERMS) then return nil end
    if not UnitStatusHasIntent(text) and not ContainsAny(text, { "status icon", "status icons", "status indicator", "status indicators" }) then return nil end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, { "classic style", "classic icon", "classic icons", "classic status icon", "classic status icons" }) then
            value = false
        elseif ContainsAny(text, { "midnight style", "midnight icon", "midnight icons", "midnight status icon", "midnight status icons" }) then
            value = true
        end
    end
    if value == nil then return nil end

    local setting = Registry and Registry:GetSetting("general.statusIconsUseMidnightStyle")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Status Icons Use Midnight Style",
        summary = "Changes the shared unit-frame status icon Midnight style toggle without changing indicator visibility.",
    } or nil
end

local function ParseUnitStatusIndicatorDetail(text)
    if not UnitStatusHasIntent(text) then return nil end

    local units = UnitStatusUnitsOrCurrent(text)
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = ResolveUnitStatusSpecOrSelected(unit, text)
    if not spec then return nil end
    if spec.value == "raidmarker" and ContainsAny(text, RAID_MARKER_SYMBOL_WORDS) and not HasStatusOffsetIntent(text) then
        return RaidMarkerSymbolAnswer()
    end

    if ContainsAny(text, { "icon pack", "icon style" }) and spec.iconStyle then
        local value = AliasValueForText(text, UNIT_STATUS_ICON_PACK_ALIASES, { "BLIZZARD", "CLASSIC", "MIDNIGHT" })
        local setting = value and Registry and Registry:GetSetting(unit .. "." .. spec.iconStyle) or nil
        if setting then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Icon Pack",
                summary = "Changes the registered icon-pack dropdown for one unit-frame status indicator.",
            }
        end
    end

    if (ContainsAny(text, { "anchor", "anchor point", "anchor position", "position dropdown" }) or StatusAnchorIntent(text))
        and type(spec.anchor) == "string" and spec.anchor ~= ""
    then
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.anchor)
        local value = setting and StatusAnchorValueForText(text, UNIT_STATUS_ANCHOR_ALIASES, setting.values or {
            "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "NAMERIGHT", "NAMELEFT",
        }) or nil
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Anchor",
                summary = "Changes the registered anchor dropdown for one unit-frame status indicator.",
            }
        end
    end

    if ContainsAny(text, { "layer", "draw layer", "draw order", "behind", "forward", "front", "backward", "backwards" })
        and type(spec.layer) == "string" and spec.layer ~= ""
    then
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.layer)
        local relativeDelta = RelativeLayerDeltaForText(text)
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if setting and (value ~= nil or relativeDelta ~= nil) then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
                label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Layer",
                summary = "Changes the registered layer slider for one unit-frame status indicator.",
            }
        end
    end

    local offsetKey
    local offsetLabel
    if ContainsAny(text, { "x offset", "offset x", "horizontal offset" }) then
        offsetKey = spec.x
        offsetLabel = "X Offset"
    elseif ContainsAny(text, { "y offset", "offset y", "vertical offset" }) then
        offsetKey = spec.y
        offsetLabel = "Y Offset"
    end
    if type(offsetKey) == "string" and offsetKey ~= "" then
        local value = FirstNumber(text)
        local setting = value ~= nil and Registry and Registry:GetSetting(unit .. "." .. offsetKey) or nil
        if setting then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " " .. offsetLabel,
                summary = "Changes the registered X/Y offset slider for one unit-frame status indicator.",
            }
        end
    end

    if ContainsAny(text, UNIT_STATUS_SIZE_TERMS) and type(spec.size) == "string" and spec.size ~= "" then
        if ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "verschiebe" }) and DetectDirection(text) then return nil end
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.size)
        if not setting then return nil end

        local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text, 1) or nil
        local value
        if relativeDelta == nil then
            if not ContainsAny(text, { "size", "font size", "text size", "icon size", "indicator size", "symbol size", "scale", "groesse" }) then return nil end
            value = FirstNumber(text)
        end
        if value == nil and relativeDelta == nil then return nil end

        return {
            kind = "changes",
            changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
            label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Size",
            summary = "Changes the registered size slider for one unit-frame status indicator.",
        }
    end

    return nil
end

local function ParseUnitStatusIndicatorMove(text)
    if not ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "verschiebe" }) then return nil end
    local direction = DetectDirection(text)
    if not direction then return nil end
    if not UnitStatusHasIntent(text) then return nil end
    local units = UnitStatusUnitsOrCurrent(text)
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = ResolveUnitStatusSpecForText(unit, text)
    if not spec then return nil end
    local key = (direction == "left" or direction == "right") and spec.x or spec.y
    if type(key) ~= "string" or key == "" then return nil end
    local setting = Registry and Registry:GetSetting(unit .. "." .. key)
    if not setting then return nil end
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    return {
        kind = "changes",
        changes = { { setting = setting, relativeDelta = amount, direction = direction } },
        label = tostring((A.UnitLabels or {})[unit] or unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Position",
        summary = "Moves a unit-frame status indicator through its real X/Y offset setting.",
    }
end

local function ParseCustomAnchorWorkflow(text)
    if not ContainsAny(text, { "custom anchor", "custom anchor picker", "anchor picker", "anchor frame picker" }) then return nil end
    if ContainsAny(text, { "cancel", "close", "stop", "abort" }) then
        local action = Registry and Registry:GetAction("cancel_custom_anchor_picker")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Cancel custom anchor picker",
            summary = "Closes the shared custom anchor picker overlay if it is active.",
        } or nil
    end
    if ContainsAny(text, { "status", "active", "is picker", "show picker" }) then
        local action = Registry and Registry:GetAction("custom_anchor_picker_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show custom anchor picker status",
            summary = "Reports whether the custom anchor picker overlay is active.",
        } or nil
    end
    if not ContainsAny(text, { "pick", "picker", "start", "open", "select", "choose" }) then return nil end
    local groups = DetectGroups(text)
    if groups[1] then
        local action = Registry and Registry:GetAction("start_group_custom_anchor_picker")
        return action and {
            kind = "action",
            action = action,
            args = { scope = groups[1] },
            label = "Start group custom anchor picker",
            summary = "Starts the shared custom anchor picker overlay for a group frame.",
        } or nil
    end
    local units = DetectUnits(text)
    local currentPageUnit = P.CurrentPageUnit
    local unit = units[1] or (type(currentPageUnit) == "function" and currentPageUnit() or nil)
    if not unit then
        local groupResolver = P.GroupScopesOrCurrentPage
        groups = type(groupResolver) == "function" and groupResolver(text) or {}
        if groups[1] then
            local action = Registry and Registry:GetAction("start_group_custom_anchor_picker")
            return action and {
                kind = "action",
                action = action,
                args = { scope = groups[1] },
                label = "Start group custom anchor picker",
                summary = "Starts the shared custom anchor picker overlay for a group frame.",
            } or nil
        end
        if ContainsAny(text, { "where", "where is", "where are", "how", "help", "settings", "setting" }) then
            return {
                kind = "answer",
                status = "info",
                text = "The custom anchor picker needs a concrete MSUF frame or the current Unit/Group page. Try: open player custom anchor picker, open target custom anchor picker, open raid custom anchor picker, or set target custom anchor to cooldownmanager.",
                summary = "Explains how to start the custom anchor picker without guessing a frame.",
            }
        end
        return nil
    end
    local action = Registry and Registry:GetAction("start_unit_custom_anchor_picker")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        label = "Start unit custom anchor picker",
        summary = "Starts the shared custom anchor picker overlay for a unit frame.",
    } or nil
end

local function CleanCustomAnchorFrameName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("[\"'`]", "")
    name = name:gsub("^frame%s+", "")
    name = name:gsub("^name%s+", "")
    name = name:gsub("^named%s+", "")
    name = name:gsub("^called%s+", "")
    name = name:gsub("^to%s+", "")
    name = name:gsub("^as%s+", "")
    name = name:gsub("[%s%.%,;:!%?]+$", "")
    name = Trim(name)
    if name == "" then return nil end
    local lower = Normalize(name)
    if lower == "none" or lower == "free" or lower == "clear" or lower == "default" or lower == "global" then return "" end
    return name
end

local function RawCustomAnchorFrameName(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local asStart = lower:find("%s+as%s+", 5)
    if lower:find("^use%s+") and asStart and lower:sub(asStart):find("custom%s+anchor") then
        return CleanCustomAnchorFrameName(raw:sub(5, asStart - 1))
    end
    local connectors = { " to ", " as ", " named ", " called ", " frame ", " name " }
    local bestEnd
    for i = 1, #connectors do
        local start = 1
        while true do
            local s, e = lower:find(connectors[i], start, true)
            if not s then break end
            if not bestEnd or e > bestEnd then bestEnd = e end
            start = e + 1
        end
    end
    if bestEnd then return CleanCustomAnchorFrameName(raw:sub(bestEnd + 1)) end
    return nil
end

local function ParseCustomAnchorSet(text, raw)
    if not ContainsAny(text, { "custom anchor", "custom anchor frame", "anchor frame name" }) then return nil end
    if not ContainsAny(text, { "set", "change", "use", "assign", "write", "apply" }) then return nil end
    local frameName = (P.CooldownManagerAnchorValueForText and P.CooldownManagerAnchorValueForText(text)) or RawCustomAnchorFrameName(raw)
    if frameName == nil then return nil end

    local groups = DetectGroups(text)
    if #groups > 0 then
        local changes = {}
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".customAnchorFrame")
            if setting then changes[#changes + 1] = { setting = setting, value = frameName } end
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = "Set group custom anchor frame",
            summary = "Writes the Group Layout custom anchor frame name directly, matching the custom anchor text box result.",
        }
    end

    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local setting = Registry and Registry:GetSetting(units[1] .. ".anchorFrameName")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = frameName } },
        label = "Set unit custom anchor frame",
        summary = "Writes the Unit Frame custom anchor frame name directly, matching the custom anchor text box result.",
    }
end

local function ParseCustomAnchorClear(text)
    if not ContainsAny(text, { "clear", "remove", "reset", "restore", "default", "defaults", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "custom anchor", "custom anchor frame", "anchor frame name" }) then return nil end
    local groups = DetectGroups(text)
    if groups[1] then
        local action = Registry and Registry:GetAction("clear_group_custom_anchor")
        return action and {
            kind = "action",
            action = action,
            args = { scope = groups[1] },
            label = "Clear " .. tostring((A.UnitLabels or {})[groups[1]] or groups[1]) .. " custom anchor",
            summary = "Clears the group-frame custom anchor frame name.",
        } or nil
    end
    local units = DetectUnits(text)
    local currentPageUnit = P.CurrentPageUnit
    local unit = units[1] or (type(currentPageUnit) == "function" and currentPageUnit() or nil)
    if not unit then
        local groupResolver = P.GroupScopesOrCurrentPage
        groups = type(groupResolver) == "function" and groupResolver(text) or {}
        if groups[1] then
            local action = Registry and Registry:GetAction("clear_group_custom_anchor")
            return action and {
                kind = "action",
                action = action,
                args = { scope = groups[1] },
                label = "Clear " .. tostring((A.UnitLabels or {})[groups[1]] or groups[1]) .. " custom anchor",
                summary = "Clears the group-frame custom anchor frame name.",
            } or nil
        end
        local action = Registry and Registry:GetAction("clear_unit_custom_anchor")
        return action and {
            kind = "action",
            action = action,
            args = { text = text },
            label = "Clear custom anchor",
            summary = "Needs a unit frame or group frame before clearing the custom anchor frame name.",
        } or nil
    end
    local action = Registry and Registry:GetAction("clear_unit_custom_anchor")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        label = "Clear " .. tostring((A.UnitLabels or {})[unit] or unit) .. " custom anchor",
        summary = "Clears the unit-frame custom anchor frame name.",
    } or nil
end

local function ParseReset(text)
    if not ContainsAny(text, { "reset", "restore", "zuruecksetzen", "default", "defaults" }) then return nil end
    if ContainsAny(text, { "factory reset", "full reset", "fullreset", "reset all settings", "reset all profiles" }) then
        local action = Registry and Registry:GetAction("factory_reset_all")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Factory reset all MSUF settings",
            summary = "Stages the shared MSUF full factory reset flow without running a slash command.",
        } or nil
    end
    if ContainsAny(text, { "profile", "profil" }) then
        local action = Registry and Registry:GetAction("reset_profile")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset active profile",
            summary = "Resets the active profile.",
        } or nil
    end
    if ContainsAny(text, { "focus kick", "focus interrupt tracker", "focus interrupt", "kick tracker" })
        and ContainsAny(text, { "position", "pos", "placement", "x", "y" })
    then
        local action = Registry and Registry:GetAction("reset_focus_kick_position")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = action.label or "Reset Focus Kick position",
            summary = "Resets the Focus Kick on-screen tracker offsets.",
        } or nil
    end
    if ContainsAny(text, { "all positions", "frame positions", "reset positions", "reset movers", "offscreen", "off screen", "broken layout", "alle positionen" }) then
        local action = Registry and Registry:GetAction("reset_all_unit_positions")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset all unit-frame positions",
            summary = "Restores default unit-frame anchors and offsets.",
        } or nil
    end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local unit = units[1]
    if ContainsAny(text, { "position", "pos", "placement", "frame position", "x", "y" }) then
        local action = Registry and Registry:GetAction("reset_unit_position")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Reset " .. tostring((A.UnitLabels or {})[unit] or unit) .. " position",
            summary = "Restores default anchor and offsets.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_unit_page")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        confirmRequired = true,
        label = "Reset " .. tostring((A.UnitLabels or {})[unit] or unit) .. " settings",
        summary = "Resets all settings on that unit page.",
    } or nil
end

local function ParseOpen(text, raw)
    local explicit = ContainsAny(text, { "open", "go to", "show settings", "show me", "find", "search", "where", "where is", "where are", "wo", "oeffne" })
    local shortcut = false
    if not explicit and DetectBoolean(text) == nil and FirstNumber(text) == nil then
        shortcut = ContainsAny(text, { "settings", "menu", "page", "options", "config", "configuration", "einstellungen", "menue", "seite" })
        if not shortcut then
            for i = 1, #PAGE_TEXT_TARGETS do
                local spec = PAGE_TEXT_TARGETS[i]
                for j = 1, #(spec.terms or {}) do
                    if text == Normalize(spec.terms[j]) then
                        shortcut = true
                        break
                    end
                end
                if shortcut then break end
            end
        end
    end
    if not explicit and not shortcut then return nil end
    local page, label = PageForText(text)
    if not page then return nil end
    local action = Registry and Registry:GetAction("open_page")
    return action and {
        kind = "action",
        action = action,
        args = { page = page, label = label, query = raw or text },
        label = "Open " .. label,
        summary = "Navigates the Dashboard.",
    } or nil
end

local function DashboardPanelForText(text)
    if ContainsAny(text, { "recovery tools", "display recovery", "recover menu", "reset tools", "dashboard recovery", "recovery panel", "recovery section", "display panel" }) then return "recovery", "recovery tools" end
    if ContainsAny(text, {
        "scaling tools", "dashboard scaling", "scale tools", "ui scale tools", "scaling panel", "scale panel",
        "scale section", "scaling section", "ui scaling panel", "ui scaling section", "menu scale", "menu scaling",
        "menu bigger", "menu smaller", "make menu bigger", "make menu smaller", "options scale", "options scaling",
        "ui scale", "ui scaling", "msuf frame scale", "msuf frames scale",
    }) then return "scaling", "scaling tools" end
    if ContainsAny(text, { "changelog", "change log", "release notes", "latest changes", "build notes", "changelog panel" }) then return "changelog", "changelog" end
    return nil, nil
end

local function ParseDashboardPanelAction(text)
    local panel, label = DashboardPanelForText(text)
    local explicit = ContainsAny(text, { "open", "show", "close", "hide", "collapse", "expand", "toggle" })
        or (panel ~= nil and P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text))
    if not explicit then return nil end
    if not panel and ContainsAny(text, { "dashboard panel", "dashboard panels" }) then
        local open
        if ContainsAny(text, { "close", "hide", "collapse" }) then
            open = false
        elseif ContainsAny(text, { "toggle" }) then
            open = nil
        else
            open = true
        end
        local action = Registry and Registry:GetAction("set_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { open = open },
            label = "Set Dashboard panel",
            summary = "Needs a specific Dashboard panel such as recovery tools, scaling tools, or changelog.",
        } or nil
    end
    if not panel then return nil end
    local open
    if ContainsAny(text, { "close", "hide", "collapse" }) then
        open = false
    elseif ContainsAny(text, { "toggle" }) then
        open = nil
    else
        open = true
    end
    local action = Registry and Registry:GetAction("set_dashboard_panel")
    return action and {
        kind = "action",
        action = action,
        args = { panel = panel, open = open },
        label = (open == false and "Close " or (open == nil and "Toggle " or "Open ")) .. label,
        summary = "Controls the persisted Dashboard panel disclosure state.",
    } or nil
end

local NAV_SECTION_TEXT_TARGETS = {
    { section = "groupframes", label = "Group Frames", terms = { "group frames", "groupframes", "raid frames", "party frames", "group frame", "groups" } },
    { section = "unitframes", label = "Frames", terms = { "frames", "unitframes", "unit frames", "unit frame", "frame list" } },
    { section = "globalstyle", label = "Appearance", terms = { "appearance", "global style", "globalstyle", "style section", "look section" } },
    { section = "modules", label = "Advanced", terms = { "advanced", "modules", "module section", "advanced menu" } },
    { section = "auras", label = "Auras", terms = { "auras", "aura section", "buffs section", "debuffs section" } },
}

local function NavSectionForText(text)
    for i = 1, #NAV_SECTION_TEXT_TARGETS do
        local spec = NAV_SECTION_TEXT_TARGETS[i]
        if ContainsAny(text, spec.terms) then return spec.section, spec.label end
    end
    return nil, nil
end

local function ParseNavRailAction(text)
    if ContainsAny(text, { "search intro", "ask msuf intro", "assistant search intro", "search help intro" }) then
        local command
        if ContainsAny(text, { "hide", "close", "dismiss", "mark seen", "mark as seen", "mark search intro seen", "dont show" }) then
            command = "seen"
        elseif ContainsAny(text, { "reset", "show again", "next time" }) then
            command = "reset"
        elseif ContainsAny(text, { "show", "open" }) then
            command = "show"
        end
        if not command then return nil end
        local action = Registry and Registry:GetAction("set_nav_search_intro")
        return action and {
            kind = "action",
            action = action,
            args = { command = command },
            label = "Set search intro",
            summary = "Controls the NavRail search intro state.",
        } or nil
    end

    if not ContainsAny(text, { "navigation section", "nav section", "sidebar section", "left nav section", "section", "navigation group", "nav group", "sidebar group" }) then return nil end
    if not ContainsAny(text, { "open", "show", "close", "hide", "collapse", "expand", "toggle" }) then return nil end
    local section, label = NavSectionForText(text)
    local open
    if ContainsAny(text, { "close", "hide", "collapse" }) then
        open = false
    elseif ContainsAny(text, { "toggle" }) then
        open = nil
    else
        open = true
    end
    local action = Registry and Registry:GetAction("set_nav_section")
    if not section then
        return action and {
            kind = "action",
            action = action,
            args = { open = open },
            label = "Set navigation section",
            summary = "Needs a specific navigation section such as Frames, Group Frames, Appearance, or Advanced.",
        } or nil
    end
    return action and {
        kind = "action",
        action = action,
        args = { section = section, open = open },
        label = (open == false and "Close " or (open == nil and "Toggle " or "Open ")) .. label .. " navigation section",
        summary = "Controls the NavRail section disclosure state.",
    } or nil
end

local function ParseMenuWindowAction(text)
    if ContainsAny(text, { "panel", "tools", "changelog", "change log", "release notes" }) then return nil end
    if not ContainsAny(text, { "menu", "dashboard", "options", "options window", "msuf menu", "msuf window" }) then return nil end
    local actionKey
    local label
    if ContainsAny(text, { "minimize", "minimise", "collapse" }) then
        actionKey = "menu_window_minimize"
        label = "Minimize MSUF menu"
    elseif ContainsAny(text, { "maximize", "maximise", "fullscreen", "full screen" }) then
        actionKey = "menu_window_maximize"
        label = "Maximize MSUF menu"
    elseif ContainsAny(text, { "restore", "unminimize", "unminimise", "show minimized" }) then
        actionKey = "menu_window_restore"
        label = "Restore MSUF menu"
    elseif ContainsAny(text, { "close", "hide" }) then
        actionKey = "menu_window_close"
        label = "Close MSUF menu"
    end
    local action = actionKey and Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = {},
        label = label,
        summary = "Controls the shared MSUF Menu2 window helpers.",
    } or nil
end

function A._ParseMenuHistoryAction(text)
    if not ContainsAny(text, {
        "menu history", "menu change", "menu changes", "menu session", "session changes",
        "msuf2 menu changes", "ui change", "ui changes", "navrail history",
        "assistant change", "assistant changes", "assistant session", "assistant edits",
    }) then return nil end
    local actionKey
    local label
    local summary
    local confirmRequired
    if ContainsAny(text, { "reset all", "reset", "restore all", "discard all", "revert all", "clear all" }) then
        actionKey = "menu_history_reset_session"
        label = "Reset menu session changes"
        summary = "Uses the same MSUF menu history-session reset helper as Shift-click Undo."
        confirmRequired = true
    elseif ContainsAny(text, { "redo", "reapply" }) then
        actionKey = "menu_history_redo"
        label = "Redo menu change"
        summary = "Uses the same MSUF menu redo helper as the NavRail Redo button."
    elseif ContainsAny(text, { "undo", "revert" }) then
        actionKey = "menu_history_undo"
        label = "Undo menu change"
        summary = "Uses the same MSUF menu undo helper as the NavRail Undo button."
    end
    local action = actionKey and Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = confirmRequired,
        label = label,
        summary = summary,
    } or nil
end

local function RegistryActionAliasScore(action, text)
    if type(action) ~= "table" then return 0 end
    if type(action.parseAliasArgs) ~= "function" and action.aliasNoArgs ~= true then return 0 end
    local aliases = action.aliases
    if type(aliases) ~= "table" or #aliases == 0 then return 0 end
    local relationText = AliasRelationText(text)
    local best = 0
    for i = 1, #aliases do
        local alias = aliases[i]
        if TextMatchesAlias and TextMatchesAlias(text, relationText, alias) then
            local score = #Compact(alias)
            if score > best then best = score end
        elseif HasPhrase(text, alias) then
            local score = #Compact(alias)
            if score > best then best = score end
        end
    end
    return best
end

local ACTION_ALIAS_COMMON_TOKENS = {
    a = true,
    an = true,
    ["and"] = true,
    ["for"] = true,
    ["in"] = true,
    my = true,
    of = true,
    on = true,
    please = true,
    the = true,
    to = true,
    with = true,
}

local function ActionAliasTokens(text)
    local out = {}
    for token in Normalize(text):gmatch("%S+") do out[#out + 1] = token end
    return out
end

local function AddActionAliasBucket(index, token, action)
    if token == "" or ACTION_ALIAS_COMMON_TOKENS[token] then return false end
    local bucket = index.byToken[token]
    if not bucket then
        bucket = {}
        index.byToken[token] = bucket
    end
    bucket[#bucket + 1] = action
    return true
end

local function EnsureRegistryActionAliasIndex(actions)
    actions = actions or {}
    if P._registryActionAliasActions == actions
        and P._registryActionAliasCount == #actions
        and type(P._registryActionAliasIndex) == "table" then
        return P._registryActionAliasIndex
    end

    local index = { byToken = {}, always = {} }
    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table"
            and (type(action.parseAliasArgs) == "function" or action.aliasNoArgs == true)
            and type(action.aliases) == "table" then
            local indexed = false
            for j = 1, #action.aliases do
                for _, token in ipairs(ActionAliasTokens(action.aliases[j])) do
                    indexed = AddActionAliasBucket(index, token, action) or indexed
                end
            end
            if not indexed then index.always[#index.always + 1] = action end
        end
    end

    P._registryActionAliasActions = actions
    P._registryActionAliasCount = #actions
    P._registryActionAliasIndex = index
    return index
end

local function AddActionAliasCandidates(candidateSet, index, tokens)
    for i = 1, #(tokens or {}) do
        local bucket = index.byToken[tokens[i]]
        if bucket then
            for j = 1, #bucket do candidateSet[bucket[j]] = true end
        end
    end
end

local function RegistryActionAliasCandidates(actions, text)
    local index = EnsureRegistryActionAliasIndex(actions)
    local candidateSet = {}
    AddActionAliasCandidates(candidateSet, index, ActionAliasTokens(text))
    local relationText = AliasRelationText(text)
    if relationText ~= text then AddActionAliasCandidates(candidateSet, index, ActionAliasTokens(relationText)) end
    for i = 1, #(index.always or {}) do candidateSet[index.always[i]] = true end

    local out = {}
    for i = 1, #actions do
        local action = actions[i]
        if candidateSet[action] then out[#out + 1] = action end
    end
    if #out == 0 then out = actions end
    P._lastRegistryActionAliasCandidateCount = #out
    P._lastRegistryActionAliasTotalCount = #actions
    return out
end

function P.ParseRegistryActionAliasShortcut(text, raw)
    local actions = Registry and Registry:AllActions() or {}
    local bestAction, bestArgs, bestMeta, bestScore
    local candidates = RegistryActionAliasCandidates(actions, text)
    for i = 1, #candidates do
        local action = candidates[i]
        local score = RegistryActionAliasScore(action, text)
        if score > 0 and (not bestScore or score > bestScore) then
            local args, meta
            if type(action.parseAliasArgs) == "function" then
                local ok, parsedArgs, parsedMeta = pcall(action.parseAliasArgs, text, raw, action)
                if ok and parsedArgs ~= false then
                    args = type(parsedArgs) == "table" and parsedArgs or {}
                    meta = type(parsedMeta) == "table" and parsedMeta or nil
                end
            elseif action.aliasNoArgs == true then
                args = {}
            end
            if args then
                bestAction, bestArgs, bestMeta, bestScore = action, args, meta, score
            end
        end
    end
    if not bestAction then return nil end
    return {
        kind = "action",
        action = bestAction,
        args = bestArgs or {},
        confirmRequired = bestAction.confirmRequired == true or (bestMeta and bestMeta.confirmRequired == true),
        label = (bestMeta and bestMeta.label) or bestAction.label or bestAction.key,
        summary = (bestMeta and bestMeta.summary) or "Runs a registered action matched by action aliases.",
    }
end

function P.ParseExactActionKeyShortcut(text, raw)
    local hay = tostring(raw or text or ""):lower()
    if not hay:find("_", 1, true) and not hay:find(".", 1, true) then return nil end
    if not hay:find("[%a_][%w_%.]*", 1) then return nil end
    local actions = Registry and Registry:AllActions() or {}
    local bestAction
    local bestKeyLen = 0
    for i = 1, #actions do
        local action = actions[i]
        local key = tostring(action and action.key or "")
        local keyLower = key:lower()
        local startPos = keyLower ~= "" and hay:find(keyLower, 1, true) or nil
        local before = startPos == nil or startPos == 1 or not hay:sub(startPos - 1, startPos - 1):match("[%w_%.]")
        local afterIndex = startPos and (startPos + #keyLower) or nil
        local after = afterIndex == nil or afterIndex > #hay or not hay:sub(afterIndex, afterIndex):match("[%w_%.]")
        if startPos and before and after then
            local combined = (keyLower .. " " .. tostring(action.label or ""):lower() .. " " .. tostring(action.type or ""):lower())
            if not combined:find("aura", 1, true)
                and not combined:find("shape", 1, true)
                and not combined:find("rounded", 1, true)
            then
                if #keyLower > bestKeyLen then
                    bestAction = action
                    bestKeyLen = #keyLower
                end
            end
        end
    end
    if not bestAction then return nil end
    return {
        kind = "action",
        action = bestAction,
        args = {},
        confirmRequired = bestAction.confirmRequired == true,
        label = bestAction.label or bestAction.key,
        summary = "Runs the registered action addressed by its exact MSUF action key.",
    }
end

P.CopyTextParts = CopyTextParts
P.RemoveUnit = RemoveUnit
P.CopyTargetsForText = CopyTargetsForText
P.CopyGroupTargetsForText = CopyGroupTargetsForText
P.ParseGroupCopy = ParseGroupCopy
P.ParseUnsupportedMixedCopy = ParseUnsupportedMixedCopy
P.ParseCopy = ParseCopy
P.BuildContextReset = BuildContextReset
P.GROUP_STATUS_ICON_ALIASES = GROUP_STATUS_ICON_ALIASES
P.GroupStatusIconForText = GroupStatusIconForText
P.GROUP_STATUS_ICON_TERMS = GROUP_STATUS_ICON_TERMS
P.FirstGroupOrDefault = FirstGroupOrDefault
P.AliasValueForText = AliasValueForText
P.GROUP_SPELL_PLACED_ALIASES = GROUP_SPELL_PLACED_ALIASES
P.GROUP_SPELL_FRAME_ALIASES = GROUP_SPELL_FRAME_ALIASES
P.GROUP_SPELL_GROWTH_ALIASES = GROUP_SPELL_GROWTH_ALIASES
P.GROUP_SPELL_ANCHOR_ALIASES = GROUP_SPELL_ANCHOR_ALIASES
P.ParseGroupSpellIndicatorAction = ParseGroupSpellIndicatorAction
P.ParseGroupCornerIndicatorReset = ParseGroupCornerIndicatorReset
P.ParseGroupStatusIconReset = ParseGroupStatusIconReset
P.ParseGroupStatusPreview = ParseGroupStatusPreview
P.ParseGroupStatusIconDetail = ParseGroupStatusIconDetail
P.UNIT_STATUS_RESET_TERMS = UNIT_STATUS_RESET_TERMS
P.ParseUnitStatusIndicatorReset = ParseUnitStatusIndicatorReset
P.ParseUnitStatusPreview = ParseUnitStatusPreview
P.ParseUnitStatusIconStyle = ParseUnitStatusIconStyle
P.ParseUnitStatusIndicatorDetail = ParseUnitStatusIndicatorDetail
P.ParseUnitStatusIndicatorMove = ParseUnitStatusIndicatorMove
P.ParseCustomAnchorWorkflow = ParseCustomAnchorWorkflow
P.CleanCustomAnchorFrameName = CleanCustomAnchorFrameName
P.RawCustomAnchorFrameName = RawCustomAnchorFrameName
P.ParseCustomAnchorSet = ParseCustomAnchorSet
P.ParseCustomAnchorClear = ParseCustomAnchorClear
P.ParseReset = ParseReset
P.ParseOpen = ParseOpen
P.DashboardPanelForText = DashboardPanelForText
P.ParseDashboardPanelAction = ParseDashboardPanelAction
P.NAV_SECTION_TEXT_TARGETS = NAV_SECTION_TEXT_TARGETS
P.NavSectionForText = NavSectionForText
P.ParseNavRailAction = ParseNavRailAction
P.ParseMenuWindowAction = ParseMenuWindowAction
